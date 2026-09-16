"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { createClient as createServiceClient } from "@/lib/supabase/service";
import { getSessionContext } from "@/lib/auth/session";
import { getActiveOrganizationId } from "@/lib/auth/active-org";
import { logger } from "@/lib/logger";
import {
  translateMessage,
  checkTokenPreservation,
  type TranslationMode,
  type SupportedLanguage,
} from "@/lib/ai/translate";
import { renderOperationalEmail } from "@/lib/email/operational-template";
import { getSiteUrl } from "@/lib/auth/site-url";
import {replyAddress} from "@/lib/email/reply-routing";
import { getEmailProvider } from "@/lib/email/resend";
import { renderEstimateEmail } from '@/lib/email/estimate-template';
import { prepareCustomerPortalUrl } from '@/lib/estimates/customer-access';
import { generateEstimateCustomerMessage, type EstimateCopyTone } from '@/lib/ai/estimate-copy';
import { emailCompanyOperationalAlert } from '@/lib/notifications/operational-email';
import { uploadEntityMedia, validateEntityImage } from '@/lib/media/entity-media';

// Solo roles de staff pueden usar la herramienta de traducción —
// chequeo explícito server-side, nunca depender solo de que el botón
// esté oculto en la UI.
async function assertStaffCanTranslate() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const role = session.memberships.find(
    (m) => m.organization_id === activeOrgId,
  )?.role;
  const allowed =
    session.isKccAdmin ||
    ["company_owner", "company_admin", "manager", "technician"].includes(
      role ?? "",
    );
  if (!allowed) throw new Error("Not authorized to use the translation tool");
}

export async function translateDraftAction(formData: FormData) {
  try {
    await assertStaffCanTranslate();
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Not authorized" };
  }

  const sourceText = formData.get("sourceText") as string;
  const targetLanguage = formData.get("targetLanguage") as SupportedLanguage;
  const mode = formData.get("mode") as TranslationMode;

  if (!sourceText || sourceText.trim().length === 0) {
    return { error: "Nothing to translate" };
  }

  try {
    const result = await translateMessage({ sourceText, targetLanguage, mode });
    return { result };
  } catch (err) {
    logger.warn("translateDraftAction failed", {
      message: err instanceof Error ? err.message : "unknown",
    });
    return { error: err instanceof Error ? err.message : "Translation failed" };
  }
}


export async function luzEstimateMessageAction(formData: FormData) {
  try {
    await assertStaffCanTranslate();
  } catch (err) {
    return { error: err instanceof Error ? err.message : 'Not authorized' };
  }

  const language = String(formData.get('language') || 'en') === 'es' ? 'es' : 'en';
  const requestedTone = String(formData.get('tone') || 'professional');
  const tone: EstimateCopyTone = ['professional', 'warm', 'concise'].includes(requestedTone)
    ? (requestedTone as EstimateCopyTone)
    : 'professional';
  const services = String(formData.get('services') || '')
    .split('\n')
    .map((value) => value.trim())
    .filter(Boolean);

  try {
    const message = await generateEstimateCustomerMessage({
      customerName: String(formData.get('customerName') || '') || null,
      vesselName: String(formData.get('vesselName') || '') || null,
      estimateNumber: String(formData.get('estimateNumber') || '') || null,
      services,
      existingMessage: String(formData.get('existingMessage') || '') || null,
      targetLanguage: language,
      tone,
    });
    return { result: { message } };
  } catch (err) {
    logger.warn('luzEstimateMessageAction failed', { message: err instanceof Error ? err.message : 'unknown' });
    return { error: err instanceof Error ? err.message : 'Luz could not prepare the message' };
  }
}

export async function startCustomerSupportAction(formData: FormData) {
  const session = await getSessionContext();
  const organizationId = await getActiveOrganizationId(session.memberships);
  if (!organizationId) return { error: 'No active organization.' };
  const subject = String(formData.get('subject') || '').trim();
  const body = String(formData.get('body') || '').trim();
  const vesselId = String(formData.get('vesselId') || '').trim() || null;
  const urgency = String(formData.get('urgency') || 'normal');
  if (subject.length < 2 || body.length < 2) return { error: 'Tell us what you need help with.' };
  const db = await createClient();
  const { data: conversationId, error } = await db.rpc('start_customer_support_conversation', {
    p_org: organizationId,
    p_vessel: vesselId,
    p_subject: urgency === 'urgent' ? `[URGENT] ${subject}` : subject,
    p_body: body,
  });
  if (error || !conversationId) return { error: error?.message ?? 'Could not start the conversation.' };
  const attachments = formData.getAll('photos').filter((value): value is File => value instanceof File && value.size > 0).slice(0, 5);
  let attachmentCount = 0;
  for (const file of attachments) {
    const invalid = validateEntityImage(file);
    if (invalid) continue;
    try {
      await uploadEntityMedia({
        organizationId, entityType: 'conversation', entityId: conversationId, vesselId,
        uploadedBy: session.userId, uploadedByRole: 'customer', visibility: 'customer_visible',
        category: 'reference', file,
      });
      attachmentCount += 1;
    } catch (mediaError) {
      logger.warn('support attachment upload failed', { message: mediaError instanceof Error ? mediaError.message : 'unknown' });
    }
  }
  void emailCompanyOperationalAlert({
    organizationId,
    eventKey: `customer-message:${conversationId}`,
    title: urgency === 'urgent' ? 'Urgent customer message' : 'New customer message',
    body: `${subject} — ${body.slice(0, 260)}${attachmentCount ? ` · ${attachmentCount} photo${attachmentCount === 1 ? '' : 's'} attached` : ''}`,
    actionPath: `/communications/${conversationId}`,
    actionLabel: 'Open conversation',
  });
  revalidatePath('/messages');
  revalidatePath('/company');
  redirect(`/communications/${conversationId}`);
}

export async function customerReplyAction(formData: FormData) {
  const conversationId = String(formData.get('conversationId') || '');
  const body = String(formData.get('body') || '').trim();
  if (!conversationId || !body) return { error: 'Write a message first.' };
  const db = await createClient();
  const { error } = await db.rpc('customer_reply_conversation', { p_conversation: conversationId, p_body: body });
  if (error) return { error: error.message };
  revalidatePath(`/communications/${conversationId}`);
  revalidatePath('/messages');
  return { success: true };
}


export async function convertConversationToServiceRequestAction(formData: FormData) {
  const conversationId = String(formData.get('conversationId') || '');
  const description = String(formData.get('description') || '').trim() || null;
  if (!conversationId) return { error: 'Conversation is required.' };
  const db = await createClient();
  const { data: requestId, error } = await db.rpc('convert_conversation_to_service_request', {
    p_conversation_id: conversationId,
    p_description: description,
  });
  if (error || !requestId) return { error: error?.message ?? 'Could not create service request.' };

  // Preserve visual context: copy support photos into the new service request
  // instead of forcing staff/customer to upload them again.
  try {
    const service = createServiceClient();
    const { data: media } = await service
      .from('entity_media_attachments')
      .select('organization_id,vessel_id,uploaded_by,uploaded_by_role,visibility,category,caption,storage_path,mime_type,size_bytes')
      .eq('entity_type', 'conversation')
      .eq('entity_id', conversationId)
      .is('deleted_at', null);
    for (const item of media ?? []) {
      const id = crypto.randomUUID();
      const ext = item.storage_path.split('.').pop() || 'bin';
      const target = `${item.organization_id}/service_request/${requestId}/${id}.${ext}`;
      const copied = await service.storage.from('portal-media').copy(item.storage_path, target);
      if (copied.error) continue;
      await service.from('entity_media_attachments').insert({
        id,
        organization_id: item.organization_id,
        entity_type: 'service_request',
        entity_id: requestId,
        vessel_id: item.vessel_id,
        uploaded_by: item.uploaded_by,
        uploaded_by_role: item.uploaded_by_role,
        visibility: item.visibility,
        category: item.category,
        caption: item.caption,
        storage_path: target,
        mime_type: item.mime_type,
        size_bytes: item.size_bytes,
      });
    }
  } catch (mediaError) {
    logger.warn('support media copy failed', { message: mediaError instanceof Error ? mediaError.message : 'unknown' });
  }

  revalidatePath(`/communications/${conversationId}`);
  revalidatePath('/service-requests');
  revalidatePath('/company');
  return { success: true, requestId };
}

export async function createConversationAction(formData: FormData) {
  const supabase = await createClient();
  const { data: conversationId, error } = await supabase.rpc(
    "get_or_create_conversation",
    {
      p_organization_id: formData.get("organizationId") as string,
      p_customer_id: formData.get("customerId") as string,
      p_vessel_id: (formData.get("vesselId") as string) || null,
      p_work_order_id: (formData.get("workOrderId") as string) || null,
      p_service_request_id: null,
      p_subject: (formData.get("subject") as string) || null,
    },
  );
  if (error || !conversationId) {
    logger.warn("createConversationAction failed", { message: error?.message });
    return { error: error?.message ?? "Could not create conversation" };
  }
  return { conversationId };
}

/**
 * Envía un mensaje de verdad: crea el registro 'queued' (reserva la
 * idempotencia), revalida server-side que la traducción no alteró
 * ningún token comercial (la UI puede haber quedado desactualizada
 * si el staff editó el texto a mano después de traducir — el
 * servidor NUNCA confía en ese estado del cliente), llama al
 * proveedor real, y registra el resultado vía el camino de servidor
 * de confianza — nunca marca 'sent' antes de que el proveedor acepte.
 */
export async function sendMessageAction(formData: FormData) {
  const conversationId = formData.get("conversationId") as string;
  const channel = (formData.get("channel") as string) || "email";
  const bodyOriginal = formData.get("bodyOriginal") as string;
  const bodyRendered = (formData.get("bodyRendered") as string) || null;

  // Revalidación server-side de tokens comerciales — nunca confía en
  // el chequeo ya hecho en el cliente. Si el staff editó el texto
  // traducido a mano y eso alteró un monto/porcentaje/número de
  // documento, el envío se rechaza acá, sin importar qué mostraba la UI.
  if (bodyRendered) {
    const check = checkTokenPreservation(bodyOriginal, bodyRendered);
    if (!check.preserved) {
      const parts: string[] = [];
      if (check.missingTokens.length > 0)
        parts.push(`missing: ${check.missingTokens.join(", ")}`);
      if (check.addedTokens.length > 0)
        parts.push(`added: ${check.addedTokens.join(", ")}`);
      if (check.unrenderedPlaceholders.length > 0)
        parts.push(
          `unresolved placeholder(s): ${check.unrenderedPlaceholders.join(", ")}`,
        );
      return {
        error: `Cannot send: the message text changed a protected value (${parts.join("; ")}). Review before sending.`,
      };
    }
  }

  const supabase = await createClient();
  const { data: messageId, error } = await supabase.rpc("send_message", {
    p_conversation_id: conversationId,
    p_channel: channel,
    p_body_original: bodyOriginal,
    p_subject: (formData.get("subject") as string) || null,
    p_body_rendered: bodyRendered,
    p_language_original: (formData.get("languageOriginal") as string) || null,
    p_language_rendered: (formData.get("languageRendered") as string) || null,
    p_customer_visible: channel !== "internal",
    p_idempotency_key:
      (formData.get("idempotencyKey") as string) || crypto.randomUUID(),
  });

  if (error || !messageId) {
    logger.warn("sendMessageAction failed", { message: error?.message });
    return { error: error?.message ?? "Could not create message" };
  }

  if (channel === "internal") {
    revalidatePath(`/communications/${conversationId}`);
    return {};
  }

  const result = await deliverQueuedMessage(messageId, conversationId);
  revalidatePath(`/communications/${conversationId}`);
  revalidatePath("/communications");
  return result;
}

/**
 * Resuelve destinatario/identidad real y llama al proveedor — la
 * única vía real de envío. Envía body_rendered cuando el staff eligió
 * "Use Translation & Send" (su presencia en el registro ES la señal
 * real de esa elección — "Send As Written" nunca la manda) — antes
 * esto se ignoraba y siempre se mandaba body_original sin importar
 * qué haya elegido el staff. El resultado del proveedor se registra
 * vía el cliente de SERVICE ROLE — la sesión normal del staff ya no
 * tiene permiso para autoafirmar 'sent' (ver migración 118).
 */
async function deliverQueuedMessage(messageId: string, conversationId: string, commercialHtml?: string) {
  const supabase = await createClient();
  const serviceClient = createServiceClient();

  const { data: message } = await supabase
    .from("messages")
    .select("body_original, body_rendered, subject, organization_id, status, conversation_id")
    .eq("id", messageId)
    .maybeSingle();
  const { data: conversation } = await supabase
    .from("conversations")
    .select("customer_id, organization_id")
    .eq("id", conversationId)
    .maybeSingle();
  if (!message || !conversation || message.conversation_id !== conversationId || message.organization_id !== conversation.organization_id)
    return { error: "Message or conversation not found" };

  if (["sent", "delivered"].includes(message.status)) return {};

  if (message.status === 'failed') {
    const retry = await supabase.rpc('retry_failed_message', {p_message_id:messageId});
    if(retry.error) return {error:retry.error.message};
  } else if(message.status !== 'queued') return {error:'This message cannot be sent in its current state.'};

  const { data: customer } = await supabase
    .from("customers")
    .select("email")
    .eq("id", conversation.customer_id)
    .maybeSingle();
  const { data: emailSettings } = await supabase
    .from("organization_email_settings")
    .select("sender_email, sender_name, signature_text, enabled, reply_to_email")
    .eq("organization_id", message.organization_id)
    .maybeSingle();

  if (!customer?.email) {
    await serviceClient.rpc("record_provider_send_result", {
      p_message_id: messageId,
      p_success: false,
      p_error: "Customer has no email on file",
    });
    return { error: "Customer has no email on file" };
  }
  if (!emailSettings?.enabled || !emailSettings?.sender_email) {
    await serviceClient.rpc("record_provider_send_result", {
      p_message_id: messageId,
      p_success: false,
      p_error: "Email sending is not enabled for this organization",
    });
    return { error: "Email sending is not enabled for this organization" };
  }

  // La traducción intencionalmente elegida (body_rendered) es lo que
  // realmente sale por el proveedor — nunca el original si el staff
  // pidió explícitamente usar la traducción.
  const outgoingText = message.body_rendered ?? message.body_original;

  const fromAddress = emailSettings.sender_name
    ? `${emailSettings.sender_name} <${emailSettings.sender_email}>`
    : emailSettings.sender_email;

  let result;
  try {
    const provider = getEmailProvider();
    result = await provider.sendEmail({
      to: customer.email,
      idempotencyKey: messageId,
      replyTo: replyAddress(conversationId,process.env.RESEND_INBOUND_DOMAIN) || emailSettings.reply_to_email || undefined,
      from: fromAddress,
      subject: message.subject ?? "Message from your service provider",
      text: outgoingText,
      html: commercialHtml ?? renderOperationalEmail({
        body: outgoingText,
        signature: emailSettings.signature_text,
        portalUrl: `${getSiteUrl()}/customer`,
      }),
    });
  } catch (err) {
    // getEmailProvider() lanza cuando falta configuración real — el
    // mensaje NUNCA queda 'sent' sin que un proveedor real lo haya
    // aceptado. Falla seguro, vía el mismo camino de servidor de
    // confianza.
    result = {
      success: false,
      error: err instanceof Error ? err.message : "Email provider unavailable",
    };
  }

  const recorded = await serviceClient.rpc("record_provider_send_result", {
    p_message_id: messageId,
    p_success: result.success,
    p_provider_message_id: result.success
      ? (result.providerMessageId ?? null)
      : null,
    p_error: result.success ? null : (result.error ?? null),
  });

  if(recorded.error) return {error:result.success ? 'The provider accepted the email, but its status could not be saved. Check the communication history before retrying.' : 'Could not save the delivery error. Check communication history.'};
  return result.success ? {} : { error: result.error || 'Email provider did not accept the message.' };
}

/** Reintenta un mensaje que falló — nunca reintenta uno ya enviado/entregado. */
export async function retryFailedMessageAction(formData: FormData) {
  const messageId = formData.get("messageId") as string;
  const conversationId = formData.get("conversationId") as string;
  const supabase = await createClient();

  const { error: retryError } = await supabase.rpc("retry_failed_message", {
    p_message_id: messageId,
  });
  if (retryError) {
    logger.warn("retry_failed_message failed", { message: retryError.message });
    return { error: retryError.message };
  }

  const result = await deliverQueuedMessage(messageId, conversationId);
  revalidatePath(`/communications/${conversationId}`);
  return result;
}

async function sendCommercialEmail(
  rpcName: string,
  args: Record<string, unknown>,
  conversationRevalidatePath?: string,
  commercialHtml?: string,
) {
  const supabase = await createClient();
  const { data: messageId, error } = await supabase.rpc(rpcName, args);
  if (error || !messageId) {
    logger.warn(`${rpcName} failed`, { message: error?.message });
    return { error: error?.message ?? "Could not create commercial message" };
  }
  const { data: message } = await supabase
    .from("messages")
    .select("conversation_id")
    .eq("id", messageId)
    .maybeSingle();
  if (message) {
    const result = await deliverQueuedMessage(
      messageId,
      message.conversation_id,
      commercialHtml,
    );
    if (conversationRevalidatePath) revalidatePath(conversationRevalidatePath);
    return {...result,messageId};
  }
  return { error: "The queued message could not be loaded. No delivery was confirmed." };
}

export async function sendEstimateEmailAction(formData: FormData) {
  const {loadEstimatePreview}=await import('@/lib/estimates/email-preview');
  const preview=await loadEstimatePreview(String(formData.get('estimateId')??''),String(formData.get('customIntro')??''));
  if(!preview.canSend)return {error:preview.issues.join(' ')};
  let commercialHtml = preview.html;
  // A customer without an account must receive an Auth-confirmed invitation,
  // not a dead link to the company workspace. The invitation is created via
  // the existing membership RPC; Supabase remains the identity authority.
  if (!preview.customerProfileId && preview.recipient) {
    try {
      const portalUrl = await prepareCustomerPortalUrl(preview.organizationId, preview.recipient);
      commercialHtml = renderEstimateEmail({
        estimate: preview.detail,
        version: preview.version,
        company: preview.organization?.name ?? 'KCC Marine Cloud',
        logo: (preview.organization?.branding_json as Record<string, unknown> | undefined)?.logo_url as string | undefined,
        intro: String(formData.get('customIntro') ?? ''),
        signature: preview.settings?.signature_text,
        portalUrl,
      });
    } catch (error) {
      return { error: error instanceof Error ? error.message : 'Could not prepare customer portal access.' };
    }
  }
  return sendCommercialEmail(
    "send_estimate_email",
    {
      p_estimate_id: formData.get("estimateId") as string,
      p_custom_intro: (formData.get("customIntro") as string) || null,
      p_idempotency_key:
        (formData.get("idempotencyKey") as string) || crypto.randomUUID(),
    },
    `/estimates/${formData.get("estimateId")}`,
    commercialHtml,
  );
}

export async function sendInvoiceEmailAction(formData: FormData) {
  return sendCommercialEmail(
    "send_invoice_email",
    {
      p_invoice_id: formData.get("invoiceId") as string,
      p_custom_intro: (formData.get("customIntro") as string) || null,
      p_idempotency_key:
        (formData.get("idempotencyKey") as string) || crypto.randomUUID(),
    },
    `/invoices/${formData.get("invoiceId")}`,
  );
}

export async function createTemplateAction(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("create_message_template", {
    p_organization_id: formData.get("organizationId") as string,
    p_name: formData.get("name") as string,
    p_category: formData.get("category") as string,
    p_language: formData.get("language") as string,
    p_subject: (formData.get("subject") as string) || null,
    p_body: formData.get("body") as string,
  });
  if (error)
    logger.warn("createTemplateAction failed", { message: error.message });
  revalidatePath("/communications/templates");
}

export async function updateTemplateAction(formData: FormData) {
  const supabase = await createClient();
  const isActiveRaw = formData.get("isActive");
  const { error } = await supabase.rpc("update_message_template", {
    p_template_id: formData.get("templateId") as string,
    p_name: (formData.get("name") as string) || null,
    p_subject: (formData.get("subject") as string) || null,
    p_body: (formData.get("body") as string) || null,
    p_is_active: isActiveRaw === null ? null : isActiveRaw === "true",
  });
  if (error) {
    logger.warn("updateTemplateAction failed", { message: error.message });
    return { error: error.message };
  }
  revalidatePath("/communications/templates");
  return {};
}

export async function updateEmailSettingsAction(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("update_email_settings", {
    p_organization_id: formData.get("organizationId") as string,
    p_sender_name: (formData.get("senderName") as string) || null,
    p_reply_to_email: (formData.get("replyToEmail") as string) || null,
    p_signature_text: (formData.get("signatureText") as string) || null,
  });
  if (error) return {error:error.message};
  revalidatePath("/company-settings");
}

export async function previewEstimateEmailAction(estimateId: string, intro: string) {
  try {
    const {loadEstimatePreview} = await import('@/lib/estimates/email-preview');
    const {detail, version, ...preview} = await loadEstimatePreview(estimateId, intro);
    return {preview};
  } catch (error) { return {error: error instanceof Error ? error.message : 'Preview unavailable'}; }
}

export async function publishAndEmailEstimateAction(formData: FormData) {
  try {
    const {loadEstimatePreview} = await import('@/lib/estimates/email-preview');
    const estimateId = String(formData.get('estimateId') ?? '');
    const preview = await loadEstimatePreview(estimateId, String(formData.get('customIntro') ?? ''));
    if(preview.fingerprint !== formData.get('fingerprint')) return {error:'The estimate changed. Refresh the preview before sending.'};
    if(!preview.canSend) return {error:'Check the customer email, company sender settings and email provider configuration before sending.'};
    if(preview.version.status === 'draft') {
      const {sendEstimateAction} = await import('@/lib/estimates/actions');
      const result = await sendEstimateAction(estimateId);
      if(result.error) return result;
    }
    return await sendEstimateEmailAction(formData);
  } catch(error) { return {error:error instanceof Error ? error.message : 'Could not send estimate'}; }
}
