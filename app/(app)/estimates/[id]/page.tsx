import {PaymentMethods} from '@/components/estimates/PaymentMethods';
import {EstimateDocument} from '@/components/estimates/EstimateDocument';
import {getLocale} from '@/lib/i18n/server';
import { ActionForm } from '@/components/ui/ActionForm';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getEstimateDetail } from '@/lib/estimates/data';
import { addLineItem, removeLineItem, updateVersionDetails, reviseEstimateAction, cancelEstimateAction } from '@/lib/estimates/actions';
import { SendButton } from '@/components/estimates/SendButton';
import { SendEstimateEmailButton } from '@/components/estimates/SendEstimateEmailButton';
import { EstimateMessageEditor } from '@/components/estimates/EstimateMessageEditor';
import { ApproveDeclineForm } from '@/components/estimates/ApproveDeclineForm';
import { MarkViewedOnMount } from '@/components/estimates/MarkViewedOnMount';
import { Card, PageTitle, Field, inputClass, SubmitButton } from '@/components/ui/primitives';
import { listEntityMedia } from '@/lib/media/entity-media';
import { EntityMediaGallery } from '@/components/media/EntityMediaGallery';
import { uploadEstimateMediaAction } from '@/lib/media/actions';
import { MediaActionForm } from '@/components/media/MediaActionForm';
import { MultiImagePicker } from '@/components/media/MultiImagePicker';
import { ApprovedEstimateMission } from '@/components/estimates/ApprovedEstimateMission';

const LINE_TYPES = ['labor', 'material', 'service', 'fee', 'discount', 'custom'];

export default async function EstimateDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const locale=await getLocale();
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const actorRole = session.memberships.find((m) => m.organization_id === activeOrgId)?.role;
  const isCustomer = actorRole === 'customer';
  const isStaff = ['company_owner', 'company_admin', 'manager', 'kcc_admin'].includes(actorRole ?? '');

  const estimate = await getEstimateDetail(id);
  if (!estimate) notFound();
  const estimateMedia = await listEntityMedia('estimate', id);
  const requestMedia = estimate.serviceRequestId ? await listEntityMedia('service_request', estimate.serviceRequestId) : [];
  const customerVisualMedia = [...requestMedia, ...estimateMedia.filter((item) => item.visibility === 'customer_visible')];

  const current = estimate.versions.find((v) => v.id === estimate.currentVersionId) ?? estimate.versions[0];
  const isActionable = isCustomer && current && ['sent', 'viewed'].includes(current.status) && (!current.validUntil || current.validUntil >= new Date().toISOString().slice(0, 10));
  const visibleLines = isCustomer ? current?.lineItems.filter((l) => l.customerVisible) : current?.lineItems;

  return (
    <div className="max-w-4xl space-y-6">
      {isCustomer && current && current.status === 'sent' && <MarkViewedOnMount versionId={current.id} />}

      <div className="flex items-start justify-between">
        <div>
          <PageTitle>
            {estimate.estimateNumber}
            {estimate.type === 'change_order' && <span className="text-cool-gray text-lg font-normal ml-2">Additional Work Authorization</span>}
          </PageTitle>
          <p className="text-xs text-cool-gray mt-1">
            {!isCustomer && estimate.customerName && `${estimate.customerName} · `}
            {estimate.vesselName}
          </p>
        </div>
        <span className="font-mono text-[10px] uppercase text-gold border border-gold-dim px-2 py-1 rounded-sm">{estimate.status}</span>
      </div>

      {current && isCustomer && <><EstimateDocument estimate={estimate} version={current} locale={locale}/><EntityMediaGallery items={customerVisualMedia} title={locale === 'es' ? 'Fotos del servicio' : 'Service photos'} /><PaymentMethods estimateId={estimate.id} locale={locale}/></>}
      {current && !isCustomer && (
        <Card>
          {current.title && <div className="text-sm font-semibold mb-1">{current.title}</div>}
          {current.customerMessage && <p className="text-xs text-cool-gray mb-4">{current.customerMessage}</p>}

          <div className="space-y-2 mb-4">
            {(visibleLines ?? []).map((li) => (
              <div key={li.id} className="flex items-center justify-between text-sm">
                <div>
                  <span>{li.description}</span>
                  <span className="text-cool-gray text-xs ml-2">
                    {li.quantity} × ${li.unitPrice.toFixed(2)}
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="font-mono">{li.lineType === 'discount' ? '-' : ''}${Math.abs(li.lineTotal).toFixed(2)}</span>
                  {isStaff && current.status === 'draft' && (
                    <form action={removeLineItem.bind(null, estimate.id, li.id)}>
                      <button type="submit" className="text-[10px] text-red-400">
                        ✕
                      </button>
                    </form>
                  )}
                </div>
              </div>
            ))}
          </div>

          <div className="border-t border-white/10 pt-3 space-y-1 text-sm">
            <div className="flex justify-between text-cool-gray">
              <span>Subtotal</span>
              <span>${current.subtotal.toFixed(2)}</span>
            </div>
            {current.discount > 0 && (
              <div className="flex justify-between text-cool-gray">
                <span>Discount</span>
                <span>-${current.discount.toFixed(2)}</span>
              </div>
            )}
            {current.tax > 0 && (
              <div className="flex justify-between text-cool-gray">
                <span>Tax</span>
                <span>${current.tax.toFixed(2)}</span>
              </div>
            )}
            <div className="flex justify-between text-base font-semibold pt-1">
              <span>Total</span>
              <span>${current.total.toFixed(2)}</span>
            </div>
          </div>

          {current.validUntil && <p className="text-[10px] font-mono uppercase text-cool-gray mt-3">Valid Until {current.validUntil}</p>}

          {estimate.type === 'change_order' && estimate.authorizedTotal != null && (
            <div className="mt-4 pt-3 border-t border-white/10 text-xs text-cool-gray">
              Authorized project total (all approved work): <span className="text-marine-white font-semibold">${estimate.authorizedTotal.toFixed(2)}</span>
            </div>
          )}
        </Card>
      )}

      {isStaff && current && <details className="premium-card rounded-2xl p-5"><summary className="cursor-pointer text-gold font-semibold">{locale==='es'?'Vista del estimado que verá el cliente':'Preview the customer estimate'}</summary><div className="pt-4 space-y-5"><EstimateDocument estimate={estimate} version={current} locale={locale}/><EntityMediaGallery items={customerVisualMedia} title={locale === 'es' ? 'Fotos visibles para el cliente' : 'Customer-visible photos'} /></div></details>}

      {isStaff && (
        <Card className="!rounded-2xl">
          <div className="flex flex-wrap items-center justify-between gap-3 mb-4"><div><p className="command-kicker">VISUAL EVIDENCE</p><h2 className="text-lg font-semibold mt-1">{locale === 'es' ? 'Fotos reales del barco' : 'Real vessel photos'}</h2><p className="text-xs text-cool-gray mt-1">{locale === 'es' ? 'Estas fotos se mostrarán en el portal del cliente junto al estimado.' : 'These photos appear in the customer portal with the estimate.'}</p></div><span className="media-count">{estimateMedia.length}</span></div>
          <EntityMediaGallery items={estimateMedia} title={locale === 'es' ? 'Galería' : 'Gallery'} />
          <MediaActionForm action={uploadEstimateMediaAction} resetOnSuccess className="space-y-3 mt-5">
            <input type="hidden" name="estimateId" value={estimate.id} />
            <div className="grid sm:grid-cols-2 gap-3">
              <select name="category" defaultValue="reference" className={inputClass}><option value="reference" className="bg-navy">Reference</option><option value="damage" className="bg-navy">Damage / issue</option><option value="diagnosis" className="bg-navy">Diagnosis</option><option value="before" className="bg-navy">Before</option><option value="progress" className="bg-navy">Progress</option><option value="after" className="bg-navy">After</option></select>
              <input name="caption" maxLength={180} placeholder={locale === 'es' ? 'Descripción opcional' : 'Optional caption'} className={inputClass} />
            </div>
            <MultiImagePicker label={locale === 'es' ? 'Agregar fotos al estimado' : 'Add estimate photos'} hint={locale === 'es' ? 'Hasta 5 fotos · se optimizan antes de subir' : 'Up to 5 photos · optimized before upload'} />
            <button type="submit" className="command-button">{locale === 'es' ? 'Subir fotos' : 'Upload photos'} →</button>
          </MediaActionForm>
        </Card>
      )}
      {/* CUSTOMER: aprobar/rechazar */}
      {isActionable && current && (
        <Card>
          <ApproveDeclineForm estimateId={estimate.id} versionId={current.id} />
        </Card>
      )}

      {/* STAFF: builder del draft */}
      {isStaff && current?.status === 'draft' && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Add Line Item</div>
          <ActionForm resetOnSuccess action={addLineItem} className="space-y-3">
            <input type="hidden" name="versionId" value={current.id} />
            <input type="hidden" name="title" value={current.title ?? ""} />
            <input type="hidden" name="estimateId" value={estimate.id} />
            <div className="grid grid-cols-2 gap-3">
              <Field label="Type">
                <select name="lineType" className={inputClass} defaultValue="service">
                  {LINE_TYPES.map((t) => (
                    <option key={t} value={t} className="bg-navy">
                      {t}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Description">
                <input name="description" required className={inputClass} />
              </Field>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Quantity">
                <input name="quantity" type="number" step="0.01" defaultValue="1" required className={inputClass} />
              </Field>
              <Field label="Unit Price">
                <input name="unitPrice" type="number" step="0.01" required className={inputClass} />
              </Field>
            </div>
            <label className="flex items-center gap-2 text-xs text-cool-gray">
              <input type="checkbox" name="customerVisible" defaultChecked /> Visible to customer
            </label>
            <SubmitButton>Add Line</SubmitButton>
          </ActionForm>

          <ActionForm action={updateVersionDetails} className="mt-6 pt-4 border-t border-white/10 space-y-3">
            <input type="hidden" name="versionId" value={current.id} />
            <input type="hidden" name="title" value={current.title ?? ""} />
            <input type="hidden" name="estimateId" value={estimate.id} />
            <div className="grid grid-cols-2 gap-3">
              <Field label="Tax ($)">
                <input name="tax" type="number" step="0.01" defaultValue={current.tax} className={inputClass} />
              </Field>
              <Field label="Valid Until">
                <input name="validUntil" type="date" defaultValue={current.validUntil ?? ''} className={inputClass} />
              </Field>
            </div>
            <Field label="Customer Message">
              <EstimateMessageEditor defaultValue={current.customerMessage ?? ''} customerName={estimate.customerName} vesselName={estimate.vesselName} estimateNumber={estimate.estimateNumber} services={current.lineItems.filter((item) => item.customerVisible).map((item) => item.description)} language={locale === 'es' ? 'es' : 'en'} />
            </Field>
            <SubmitButton>Save Details</SubmitButton>
          </ActionForm>

          <div className="mt-4">
            <SendEstimateEmailButton estimateId={estimate.id} publishDraft />
          </div>
        </Card>
      )}

      {/* STAFF: acciones de lifecycle sobre versiones no-draft */}
      {isStaff && current && current.status !== 'draft' && !['approved', 'cancelled'].includes(estimate.status) && (
        <Card>
          <div className="flex gap-3 flex-wrap">
            <form action={reviseEstimateAction.bind(null, estimate.id)}>
              <button type="submit" className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
                Revise (New Version)
              </button>
            </form>
            <form action={cancelEstimateAction.bind(null, estimate.id)}>
              <button type="submit" className="text-[10px] font-mono uppercase border border-red-500/30 text-red-400 px-3 py-1.5 rounded-sm">
                Cancel Estimate
              </button>
            </form>
          </div>
        </Card>
      )}

      {isStaff && current && current.status !== 'draft' && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Customer Communication</div>
          <SendEstimateEmailButton estimateId={estimate.id} />
        </Card>
      )}

      {isStaff && estimate.status === 'approved' && (
        <ApprovedEstimateMission estimateId={estimate.id} workOrderId={estimate.workOrderId} locale={locale} />
      )}

      {!isStaff && estimate.workOrderId && (
        <Link href={`/work-orders/${estimate.workOrderId}`} className="text-[10px] font-mono uppercase text-gold">
          View Work Order →
        </Link>
      )}

      {/* Historial de versiones */}
      {estimate.versions.length > 1 && (
        <div>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-cool-gray mb-2">Version History</div>
          <div className="space-y-1">
            {estimate.versions.map((v) => (
              <div key={v.id} className="text-xs text-cool-gray flex justify-between">
                <span>
                  V{v.versionNumber} — {v.status}
                </span>
                <span>${v.total.toFixed(2)}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
