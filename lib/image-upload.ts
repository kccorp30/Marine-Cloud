/** Resize phone photographs before submitting to the existing server validator. */
export async function prepareImage(form:FormData,field:string){
 const file=form.get(field);if(!(file instanceof File)||!file.size)return;
 if(file.size<=2*1024*1024&&['image/jpeg','image/png','image/webp'].includes(file.type))return;
 const url=URL.createObjectURL(file);
 try{const img=new Image();img.src=url;await img.decode();const ratio=Math.min(1,1600/Math.max(img.width,img.height));const canvas=document.createElement('canvas');canvas.width=Math.round(img.width*ratio);canvas.height=Math.round(img.height*ratio);const ctx=canvas.getContext('2d');if(!ctx)throw Error('Image processing unavailable');ctx.drawImage(img,0,0,canvas.width,canvas.height);const blob=await new Promise<Blob>((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(Error('Unable to resize image')),'image/webp',.82));form.set(field,new File([blob],'upload.webp',{type:'image/webp'}));}finally{URL.revokeObjectURL(url);}
}
