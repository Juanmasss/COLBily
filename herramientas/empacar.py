"""Vuelve a armar cloudflare/sitio (para subir como carpeta) y cloudflare/worker.js (un solo archivo)
después de cambiar index.html u otro archivo de la app.   Uso:  python herramientas/empacar.py"""
import os, shutil, json, base64, mimetypes
APP=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # la carpeta COLBily
SITIO=f'{APP}/cloudflare/sitio'
ARCH=['index.html','excel.js','emojis.json','manifest.webmanifest','sql/instalar.sql',
      'icons/icon-512.png','icons/icon-192.png','icons/apple-touch-icon.png','icons/favicon-32.png','icons/favicon-16.png','icons/favicon.ico']
shutil.rmtree(SITIO,ignore_errors=True)
for a in ARCH:
    os.makedirs(os.path.dirname(f'{SITIO}/{a}'),exist_ok=True); shutil.copy(f'{APP}/{a}',f'{SITIO}/{a}')
TIPOS={'.html':'text/html; charset=utf-8','.js':'application/javascript; charset=utf-8','.json':'application/json; charset=utf-8',
       '.webmanifest':'application/manifest+json','.sql':'text/plain; charset=utf-8','.png':'image/png','.ico':'image/x-icon'}
fs={}
for a in ARCH:
    ext=os.path.splitext(a)[1]; raw=open(f'{APP}/{a}','rb').read()
    if ext in ('.png','.ico'): fs['/'+a]={'t':TIPOS[ext],'b':1,'d':base64.b64encode(raw).decode()}
    else: fs['/'+a]={'t':TIPOS[ext],'d':raw.decode('utf-8')}
w='''/* COLBily · Toda tu plata en un solo lugar.
   Worker de Cloudflare de un solo archivo: trae la app completa adentro
   (index.html, excel.js, emojis, íconos y sql/instalar.sql).
   Cómo subirlo: Cloudflare › Workers & Pages › Create › Worker › Edit code,
   borra lo que trae, pega TODO este archivo y toca Deploy.
   No guarda datos: cada persona conecta su propio Supabase desde la app. */
const ARCHIVOS = '''+json.dumps(fs,ensure_ascii=False)+''';

export default {
  async fetch(request) {
    const url = new URL(request.url);
    let ruta = decodeURIComponent(url.pathname);
    if (ruta === '/' || ruta === '') ruta = '/index.html';
    const f = ARCHIVOS[ruta];
    if (!f) return new Response('No encontramos esta página.', { status: 404, headers: { 'content-type': 'text/plain; charset=utf-8' } });
    const cuerpo = f.b ? Uint8Array.from(atob(f.d), c => c.charCodeAt(0)) : f.d;
    return new Response(cuerpo, { headers: {
      'content-type': f.t,
      'cache-control': ruta === '/index.html' ? 'no-cache' : 'public, max-age=3600',
      'x-content-type-options': 'nosniff'
    } });
  }
};
'''
open(f'{APP}/cloudflare/worker.js','w').write(w)
print('worker', len(w.encode())//1024,'KB')
shutil.make_archive(f'{APP}/cloudflare/sitio','zip',SITIO)
print('sitio.zip listo')
