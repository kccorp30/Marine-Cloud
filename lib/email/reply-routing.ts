export function replyAddress(conversationId:string,domain:string|undefined){
 if(!domain||!/^([a-z0-9-]+\.)+[a-z]{2,}$/i.test(domain)||!/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/.test(conversationId))return undefined;
 return `reply+${conversationId}@${domain.toLowerCase()}`;
}
export function parseReplyRecipient(address:string,domain:string){
 const clean=(address.match(/<([^<>]+)>/)?.[1]||address).trim().toLowerCase();
 const match=clean.match(/^reply\+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})@(.+)$/);
 return match&&match[2]===domain.toLowerCase()?match[1]:null;
}
export function senderEmail(value:string){return (value.match(/<([^<>]+)>/)?.[1]||value).trim().toLowerCase();}
