import Link from 'next/link';
export function SmartProfile({name,photo,subtitle,status,children}:{name:string;photo?:string|null;subtitle:string;status?:React.ReactNode;children?:React.ReactNode}){
 return <section className="kcc-profile"><div className="kcc-portrait">{photo?<img src={photo} alt=""/>:<span translate="no">{name.split(/\s+/).slice(0,2).map(n=>n[0]).join('')}</span>}</div><div className="kcc-profile-identity"><p className="kcc-eyebrow">{subtitle}</p><h2>{name}</h2>{status&&<div className="mt-3">{status}</div>}</div>{children&&<div className="kcc-profile-context">{children}</div>}</section>;
}
export function ContactActions({phone,email,labels}:{phone?:string|null;email?:string|null;labels:{call:string;email:string;whatsapp:string}}){
 const tel=phone?.replace(/[^+0-9]/g,'');return <div className="kcc-actions">{tel&&<><a className="kcc-action" href={`tel:${tel}`}><span aria-hidden="true">↗</span>{labels.call}</a><a className="kcc-action" href={`https://wa.me/${tel.replace(/\D/g,'')}`} target="_blank" rel="noopener noreferrer">{labels.whatsapp}</a></>}{email&&<a className="kcc-action" href={`mailto:${email}`}>{labels.email}</a>}</div>;
}
export function WorkspaceSection({title,children,href,action}:{title:string;children:React.ReactNode;href?:string;action?:string}){return <section className="kcc-section"><header><h2>{title}</h2>{href&&<Link href={href}>{action} →</Link>}</header>{children}</section>;}
