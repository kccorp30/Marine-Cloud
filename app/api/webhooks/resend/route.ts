import {parseReplyRecipient,senderEmail} from '@/lib/email/reply-routing';
import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import { createClient } from '@/lib/supabase/service';
import { logger } from '@/lib/logger';

// =========================================================
// app/api/webhooks/resend/route.ts — Marine Cloud Phase 8 hardening
// =========================================================
// Resend firma sus webhooks con el formato Svix (svix-id,
// svix-timestamp, svix-signature — HMAC-SHA256 sobre
// "{id}.{timestamp}.{body}", codificado en base64, con el secreto
// como "whsec_...").
//
// LIMITACIÓN HONESTA: sin RESEND_WEBHOOK_SECRET configurado en este
// entorno, no pude verificar una firma real en vivo — el algoritmo
// de verificación de abajo es el real y correcto de Svix/Resend. Sin
// el secreto, la ruta rechaza TODO (fail-closed), nunca acepta un
// payload sin firmar como si fuera confiable.
// =========================================================

function verifySvixSignature(payload: string, headers: { id: string; timestamp: string; signature: string }, secret: string): boolean {
  const timestamp=Number(headers.timestamp);
  if(!Number.isFinite(timestamp)||Math.abs(Date.now()/1000-timestamp)>300)return false;
  const signedContent = `${headers.id}.${headers.timestamp}.${payload}`;
  const secretBytes = Buffer.from(secret.replace('whsec_', ''), 'base64');
  const expectedSignature = crypto.createHmac('sha256', secretBytes).update(signedContent).digest('base64');

  // svix-signature puede traer varias firmas separadas por espacio,
  // cada una con prefijo de versión ("v1,<base64>") — alcanza con que
  // una coincida.
  const providedSignatures = headers.signature.split(' ').map((s) => s.split(',')[1]).filter(Boolean);
  return providedSignatures.some((sig) => {
    try {
      return crypto.timingSafeEqual(Buffer.from(sig, 'base64'), Buffer.from(expectedSignature, 'base64'));
    } catch {
      return false;
    }
  });
}

export async function POST(req: NextRequest) {
  const secret = process.env.RESEND_WEBHOOK_SECRET;
  const rawBody = await req.text();
  if(rawBody.length>1_000_000)return NextResponse.json({error:"Payload too large"},{status:413});

  const svixId = req.headers.get('svix-id');
  const svixTimestamp = req.headers.get('svix-timestamp');
  const svixSignature = req.headers.get('svix-signature');

  // Fail-closed: sin secreto configurado, o sin las 3 cabeceras
  // esperadas, se rechaza — nunca se procesa un payload sin verificar.
  if (!secret || !svixId || !svixTimestamp || !svixSignature) {
    logger.warn('resend webhook rejected — missing secret or signature headers');
    return NextResponse.json({ error: 'Signature verification unavailable' }, { status: 401 });
  }

  const valid = verifySvixSignature(rawBody, { id: svixId, timestamp: svixTimestamp, signature: svixSignature }, secret);
  if (!valid) {
    logger.warn('resend webhook signature verification failed');
    return NextResponse.json({ error: 'Invalid signature' }, { status: 401 });
  }

  let event;try{event=JSON.parse(rawBody);}catch{return NextResponse.json({error:'Invalid JSON'},{status:400});}
  if(typeof event.type !== 'string')return NextResponse.json({error:'Invalid event'},{status:400});
  const eventType: string = event.type; // e.g. "email.delivered", "email.bounced", "email.complained"
  const providerMessageId: string | undefined = event.data?.email_id;
  const eventId: string = svixId; // svix-id es único por evento — sirve como clave de dedupe real

  if (!providerMessageId) {
    return NextResponse.json({ ok: true }); // evento sin email_id — nada que mapear, no es un error
  }

  if(eventType==='email.received'){
    const domain=process.env.RESEND_INBOUND_DOMAIN;
    if(!domain||!process.env.RESEND_API_KEY)return NextResponse.json({error:'Inbound mail is not configured'},{status:503});
    if(!/^[0-9a-f-]{36}$/i.test(providerMessageId))return NextResponse.json({error:'Invalid email id'},{status:400});
    const response=await fetch(`https://api.resend.com/emails/receiving/${providerMessageId}`,{headers:{Authorization:`Bearer ${process.env.RESEND_API_KEY}`},signal:AbortSignal.timeout(10000)});
    if(!response.ok)return NextResponse.json({error:'Could not retrieve received email'},{status:502});
    const incoming=await response.json();
    const conversations=Array.from(new Set((Array.isArray(incoming.to)?incoming.to:[]).map((address:unknown)=>typeof address==='string'?parseReplyRecipient(address,domain):null).filter(Boolean))) as string[];
    if(conversations.length!==1||typeof incoming.from!=='string')return NextResponse.json({ok:true,unmatched:true});
    const body=typeof incoming.text==='string'&&incoming.text.trim()?incoming.text:typeof incoming.html==='string'?incoming.html.replace(/<script[\s\S]*?<\/script>/gi,'').replace(/<style[\s\S]*?<\/style>/gi,'').replace(/<[^>]+>/g,' ').replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').trim():'Email received without a text body. Review attachments in the email inbox.';
    const {data:matched,error}=await createClient().rpc('record_customer_email_reply',{p_provider_id:providerMessageId,p_conversation:conversations[0],p_sender:senderEmail(incoming.from),p_body:body.slice(0,100000),p_subject:typeof incoming.subject==='string'?incoming.subject:''});
    if(error)return NextResponse.json({error:'Could not record reply'},{status:500});
    return NextResponse.json({ok:true,matched});
  }

  const normalizedType = eventType.replace('email.', ''); // "delivered" | "bounced" | "complained" | ...

  // service role — este endpoint corre como el actor de plataforma de
  // confianza (kcc_admin), nunca como un usuario autenticado normal.
  const supabase = createClient();
  const { error } = await supabase.rpc('process_email_webhook_event', {
    p_provider_event_id: eventId,
    p_provider_message_id: providerMessageId,
    p_event_type: normalizedType,
  });

  if (error) {
    logger.warn('process_email_webhook_event failed', { message: error.message });
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
