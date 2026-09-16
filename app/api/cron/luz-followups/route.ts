import {NextRequest,NextResponse} from 'next/server';
import {timingSafeEqual} from 'node:crypto';
import {createClient} from '@/lib/supabase/service';
import {getEmailProvider} from '@/lib/email/resend';
import {renderOperationalEmail} from '@/lib/email/operational-template';
import {replyAddress} from '@/lib/email/reply-routing';
import {getSiteUrl} from '@/lib/auth/site-url';

export async function GET(request:NextRequest){
 const secret=process.env.CRON_SECRET;const incoming=request.headers.get('authorization')||'';const expected=`Bearer ${secret}`;
 if(!secret||Buffer.byteLength(incoming)!==Buffer.byteLength(expected)||!timingSafeEqual(Buffer.from(incoming),Buffer.from(expected)))return NextResponse.json({error:'Unauthorized'},{status:401});
 if(!process.env.RESEND_API_KEY)return NextResponse.json({error:'Follow-up delivery is not enabled: RESEND_API_KEY is missing'},{status:503});
 const db=createClient();let sent=0,skipped=0,failed=0;
 for(let i=0;i<10;i++){
  const {data:job,error}=await db.rpc('claim_luz_followup');if(error)return NextResponse.json({error:'Could not load the follow-up queue'},{status:500});if(!job)break;if(job.skipped){skipped++;continue;}
  const replyTo=process.env.RESEND_INBOUND_DOMAIN?replyAddress(job.conversationId,process.env.RESEND_INBOUND_DOMAIN):undefined;
  let result;
  try{
   result=await getEmailProvider().sendEmail({to:job.recipient,from:job.fromName?`${job.fromName} <${job.fromEmail}>`:job.fromEmail,replyTo:replyTo||undefined,subject:job.subject,text:job.body,html:renderOperationalEmail({body:job.body,signature:job.signature,portalUrl:`${getSiteUrl()}/estimates/${job.estimateId}`}),idempotencyKey:job.messageId});
  }catch(err){result={success:false,error:err instanceof Error?err.message:'Email provider unavailable'};}
  const recorded=await db.rpc('record_provider_send_result',{p_message_id:job.messageId,p_success:result.success,p_provider_message_id:result.providerMessageId||null,p_error:result.error||null});
  const ok=result.success&&!recorded.error;
  await db.from('luz_estimate_followups').update({status:ok?'sent':'failed',reason:ok?null:recorded.error?'Provider result requires manual review':result.error||'Delivery failed'}).eq('id',job.jobId);
  if(ok)sent++;else failed++;
 }
 return NextResponse.json({sent,skipped,failed,inboundReplies:!!process.env.RESEND_INBOUND_DOMAIN});
}
