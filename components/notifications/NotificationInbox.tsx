'use client';
import {useEffect,useState} from 'react';
import {loadNotificationInbox} from '@/lib/notifications/actions';
import {NotificationItem} from './NotificationItem';
import {useCommandCopy} from '@/components/ui/LocaleProvider';
export function NotificationInbox(){const {t}=useCommandCopy();const [rows,setRows]=useState<Awaited<ReturnType<typeof loadNotificationInbox>>|null>(null);const [error,setError]=useState(false);useEffect(()=>{let active=true;loadNotificationInbox().then(result=>{if(active)setRows(result);}).catch(()=>{if(active)setError(true);});return()=>{active=false};},[]);return <div>{error?<p role="alert">{t.unavailable}</p>:rows===null?<p role="status">{t.loading}</p>:rows.length?rows.map(row=><NotificationItem key={row.notification.id} {...row} severityLabel={row.notification.severity}/>):<p>{t.noAlerts}</p>}</div>;}
