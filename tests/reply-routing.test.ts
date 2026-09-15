import {describe,it,expect} from 'vitest';
import {replyAddress,parseReplyRecipient,senderEmail} from '../lib/email/reply-routing';
const id='00000000-0000-4000-8000-000000000012';
describe('conversation email routing',()=>{
 it('routes only a UUID mailbox on the configured inbound domain',()=>{expect(parseReplyRecipient(`reply+${id}@inbound.example.com`,'inbound.example.com')).toBe(id);expect(parseReplyRecipient(`reply+${id}@inbound.example.com.attacker.test`,'inbound.example.com')).toBeNull();expect(parseReplyRecipient(`other+${id}@inbound.example.com`,'inbound.example.com')).toBeNull();});
 it('does not generate a reply address without valid routing configuration',()=>{expect(replyAddress(id,undefined)).toBeUndefined();expect(replyAddress(id,'https://bad.test')).toBeUndefined();expect(replyAddress(id,'inbound.example.com')).toBe(`reply+${id}@inbound.example.com`);});
 it('extracts addresses without treating display names as identities',()=>{expect(senderEmail('Marine Owner <Owner@Example.com>')).toBe('owner@example.com');expect(senderEmail('other@example.com')).toBe('other@example.com');});
});
