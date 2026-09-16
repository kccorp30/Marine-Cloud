"use client";
import {ActionForm} from '@/components/ui/ActionForm';
import {useCommandCopy} from '@/components/ui/LocaleProvider';
import {setMonthlyFee} from '@/lib/launch/monthly-fee';
export function MonthlyFeeForm({organizationId,amount}:{organizationId:string;amount:number|null}){
 const {locale}=useCommandCopy();const es=locale==='es';
 return <details className="premium-card rounded-2xl p-5"><summary className="font-semibold cursor-pointer">{es?'Cobro mensual fijo':'Fixed monthly fee'} {amount!=null?`· USD ${amount}`:''}</summary><ActionForm action={setMonthlyFee} className="space-y-4 mt-4"><input type="hidden" name="organizationId" value={organizationId}/><label className="block">{es?'Importe mensual (USD)':'Monthly amount (USD)'}<input required name="amount" type="number" min="0.01" max="9999999" step="0.01" defaultValue={amount??''} className="block w-full mt-2 rounded-xl p-3 bg-white/5 border border-white/15"/></label><label className="block">{es?'Condiciones de pago':'Payment terms'}<textarea required name="terms" rows={2} className="block w-full mt-2 rounded-xl p-3 bg-white/5 border border-white/15"/></label><p className="text-sm text-cool-gray">{es?'Configura el importe acordado con la compañía. El cobro se gestiona manualmente; no se debita ninguna tarjeta.':'Sets the agreed company fee. Collection is manual; no card is charged.'}</p><button className="command-action">{es?'Guardar cobro mensual':'Save monthly fee'}</button></ActionForm></details>;
}
