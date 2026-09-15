import {describe,it,expect,vi,beforeEach,afterEach} from 'vitest';
import {NextRequest} from 'next/server';
const mocks=vi.hoisted(()=>({rpc:vi.fn(),send:vi.fn(),update:vi.fn(),eq:vi.fn()}));
vi.mock('server-only',()=>({}));
vi.mock('@/lib/supabase/service',()=>({createClient:()=>({rpc:mocks.rpc,from:()=>({update:mocks.update})})}));
vi.mock('@/lib/email/resend',()=>({getEmailProvider:()=>({sendEmail:mocks.send})}));
vi.mock('@/lib/auth/site-url',()=>({getSiteUrl:()=> 'https://marine.example.test'}));
import {GET} from '../app/api/cron/luz-followups/route';
beforeEach(()=>{vi.clearAllMocks();vi.stubEnv('CRON_SECRET','test-secret');vi.stubEnv('LUZ_FOLLOWUPS_ENABLED','true');vi.stubEnv('RESEND_API_KEY','test-only');vi.stubEnv('RESEND_INBOUND_DOMAIN','inbound.example.test');mocks.update.mockReturnValue({eq:mocks.eq});mocks.eq.mockResolvedValue({error:null});});
afterEach(()=>vi.unstubAllEnvs());
describe('Luz scheduled dispatch',()=>{
 it('rejects missing authorization without accessing the queue',async()=>{const r=await GET(new NextRequest('https://marine.example.test/api/cron/luz-followups'));expect(r.status).toBe(401);expect(mocks.rpc).not.toHaveBeenCalled();expect(mocks.send).not.toHaveBeenCalled();});
 it('stays disabled until inbound replies are configured',async()=>{vi.stubEnv('RESEND_INBOUND_DOMAIN','');const r=await GET(new NextRequest('https://marine.example.test/api/cron/luz-followups',{headers:{authorization:'Bearer test-secret'}}));expect(r.status).toBe(503);expect(mocks.rpc).not.toHaveBeenCalled();});
 it('records provider acceptance only after sending, with the queued message key',async()=>{
 const id='00000000-0000-4000-8000-000000000012';mocks.rpc.mockResolvedValueOnce({data:{jobId:'job',messageId:'message',conversationId:id,recipient:'customer@example.test',fromEmail:'service@example.test',subject:'Review',body:'Total USD 100',estimateId:'estimate'},error:null}).mockResolvedValueOnce({error:null}).mockResolvedValueOnce({data:null,error:null});mocks.send.mockResolvedValue({success:true,providerMessageId:'provider-id'});
 const r=await GET(new NextRequest('https://marine.example.test/api/cron/luz-followups',{headers:{authorization:'Bearer test-secret'}}));expect(await r.json()).toEqual({sent:1,skipped:0,failed:0});expect(mocks.send).toHaveBeenCalledWith(expect.objectContaining({idempotencyKey:'message',replyTo:`reply+${id}@inbound.example.test`}));expect(mocks.rpc).toHaveBeenCalledWith('record_provider_send_result',expect.objectContaining({p_success:true,p_provider_message_id:'provider-id'}));expect(mocks.send.mock.invocationCallOrder[0]).toBeLessThan(mocks.rpc.mock.invocationCallOrder[1]);
 });
});
