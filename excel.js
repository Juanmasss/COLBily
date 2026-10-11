/* Finanzas · descargar movimientos en Excel
   Arma el .xlsx en el mismo teléfono o computador, sin librerías ni servidor:
   hojas con tablas, fórmulas y gráficas de Excel de verdad (se pueden editar y se
   actualizan si cambias algo en la hoja Movimientos).
   La página lo baja solo al tocar "Descargar" en Ajustes. Devuelve un Blob que la
   página descarga y suelta: no se guarda nada en la app ni en la base. */
(function(){
'use strict';

/* ================= utilidades ================= */
const XE=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
/* quita lo que no se puede guardar en XML (controles, mitades de emoji sueltas) */
function limpio(s){
  s=String(s??''); let o='';
  for(let i=0;i<s.length;i++){
    const c=s.charCodeAt(i);
    if(c>=0xD800&&c<=0xDBFF){ const d=s.charCodeAt(i+1); if(d>=0xDC00&&d<=0xDFFF){ o+=s[i]+s[i+1]; i++; } continue; }
    if(c>=0xDC00&&c<=0xDFFF) continue;
    if(c<32&&c!==9&&c!==10&&c!==13) continue;
    if(c===0xFFFE||c===0xFFFF) continue;
    o+=s[i];
  }
  return o.slice(0,32000);
}
const COL=n=>{ let s=''; n++; while(n){ const m=(n-1)%26; s=String.fromCharCode(65+m)+s; n=(n-m-1)/26; } return s; };
const REF=(c,r)=>COL(c)+(r+1);                      // c y r empiezan en 0
const ABS=(c,r)=>'$'+COL(c)+'$'+(r+1);
const HQ=n=>"'"+String(n).replace(/'/g,"''")+"'";   // nombre de hoja entre comillas
const r2=v=>Math.round((Number(v)||0)*100)/100;
const numX=v=>{ v=Number(v); return isFinite(v)?String(Math.round(v*1e6)/1e6):'0'; };
const hex=c=>String(c||'#000000').replace('#','').toUpperCase().slice(0,6);
const serial=f=>{ const [y,m,d]=f.split('-').map(Number); return (Date.UTC(y,m-1,d)-Date.UTC(1899,11,30))/864e5; };
const DIAS=['domingo','lunes','martes','miércoles','jueves','viernes','sábado'];
const ORDEN_DIAS=['lunes','martes','miércoles','jueves','viernes','sábado','domingo'];
const MES3=['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
const MESL=['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
const iso=(y,m,d)=>`${y}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
const fechaD=f=>new Date(f+'T00:00:00');
/* $1,2M / $850k en ejes y etiquetas de las gráficas */
const FMT_K='[>=1000000]"$"0.0,,"M";[>=1000]"$"0,"k";"$"0';
const FMT_PESOS='"$"#,##0';

/* ================= estilos de celda =================
   Cada número es un índice en cellXfs (abajo, en estilosXml). */
const S={base:0,titulo:1,nota:2,enc:3,txt:4,fecha:5,pesos:6,neto:7,pct:8,ent:9,
  totTxt:10,totPesos:11,totNeto:12,totEnt:13,totPct:14,seccion:15,kpiLab:16,kpiPesos:17,kpiNeto:18,kpiEnt:19,
  encDer:20,pesosUp:21,pesosDown:22,subt:23};

/* ================= una hoja ================= */
class Hoja{
  constructor(nombre,{cuadricula=false}={}){
    this.n=nombre; this.c=new Map(); this.anchos={}; this.altos={};
    this.graficas=[]; this.tabla=null; this.congelar=false; this.cuadricula=cuadricula; this.maxC=0; this.maxR=0;
    this.encs=new Set();   // filas de títulos de tabla
  }
  put(c,r,x){ let f=this.c.get(r); if(!f){ f=new Map(); this.c.set(r,f); } f.set(c,x);
    if(c>this.maxC) this.maxC=c; if(r>this.maxR) this.maxR=r; }
  txt(c,r,v,s=S.txt){ this.put(c,r,{t:'s',v:limpio(v),s}); }
  num(c,r,v,s=S.pesos){ this.put(c,r,{t:'n',v:r2(v),s}); }
  fx(c,r,o,s=S.pesos){ this.put(c,r,{t:'f',f:o.f,v:Number(o.v)||0,s}); }   // o = {f:fórmula, v:valor ya calculado}
  fxs(c,r,o,s=S.txt){ this.put(c,r,{t:'fs',f:o.f,v:limpio(o.v),s}); }      // fórmula que da texto
  val(c,r){ const f=this.c.get(r), x=f&&f.get(c); return x?x.v:undefined; }
  ancho(c,w){ this.anchos[c]=w; }
}

/* ================= el libro ================= */
async function crear(o){
  const det=!!o.detalles;
  const COLOR=hex(o.color||'#2A78D6');
  const SERIE=(o.serie&&o.serie.length?o.serie:['#2a78d6','#eb6834','#1baf7a','#eda100','#e87ba4','#008300','#4a3aa7','#e34948']).map(hex);
  const UP=hex(o.up||'#047857'), DOWN=hex(o.down||'#E11D48'), GRIS='9AA0A8';

  /* ---------- las filas, ya con lo que se escribe en cada columna ---------- */
  const TIPO={ingreso:'Ingreso',gasto:'Gasto',pago_tc:'Pago a tarjeta',traslado:'Traslado'};
  const F=(o.filas||[]).map(x=>{
    const r={...x,monto:r2(x.monto)};
    const esGI=r.tipo==='gasto'||r.tipo==='ingreso';
    r.cuadre=!!r.cuadre&&esGI;
    r.tipoL=r.cuadre?(r.tipo==='ingreso'?'Cuadre (sube)':'Cuadre (baja)'):(TIPO[r.tipo]||r.tipo);
    r.dia=DIAS[fechaD(r.fecha).getDay()];
    r.cat=esGI?limpio(r.categoria||'Sin categoría'):'';
    r.cuenta=limpio(r.cuenta||''); r.desde=limpio(r.desde||''); r.bolsillo=limpio(r.bolsillo||'');
    r.origen=r.extracto?'Extracto':'Anotado';
    return r;
  });
  const hay=t=>F.some(r=>r.tipoL===t);
  const hayG=hay('Gasto'), hayI=hay('Ingreso'), hayP=hay('Pago a tarjeta'), hayT=hay('Traslado');
  const hayCuadre=F.some(r=>r.cuadre);

  /* ---------- columnas de la hoja Movimientos ---------- */
  const COLS=[
    {k:'fecha',h:'Fecha',w:11.5,s:S.fecha,v:r=>r.fecha},
    {k:'dia',h:'Día',w:11,v:r=>r.dia},
    {k:'tipo',h:'Tipo',w:15,v:r=>r.tipoL},
    {k:'cuenta',h:'Cuenta o tarjeta',w:20,v:r=>r.cuenta},
    ...(hayP||hayT?[{k:'desde',h:'Desde',w:18,v:r=>r.desde}]:[]),
    ...(det&&F.some(r=>r.bolsillo)?[{k:'bolsillo',h:'Bolsillo',w:16,v:r=>r.bolsillo}]:[]),
    ...(det?[{k:'cat',h:'Categoría',w:24,v:r=>r.cat},{k:'nota',h:'Descripción',w:42,v:r=>limpio(r.nota||'')}]:[]),
    {k:'monto',h:'Monto',w:14,s:S.pesos,v:r=>r.monto,n:true},
    ...(det&&F.some(r=>r.cuotas>1)?[{k:'cuotas',h:'Cuotas',w:8,s:S.ent,v:r=>r.cuotas>1?r.cuotas:null,n:true}]:[]),
    ...(F.some(r=>r.extracto)?[{k:'origen',h:'De dónde',w:11,v:r=>r.origen}]:[])
  ];
  const CI={}; COLS.forEach((c,i)=>CI[c.k]=i);
  const MOV='Movimientos';
  const M=k=>`${HQ(MOV)}!$${COL(CI[k])}:$${COL(CI[k])}`;

  /* ---------- fórmulas que suman la hoja Movimientos (y el mismo cálculo aquí, para el valor guardado) ----------
     Cada condición: {k:'tipo'|'cat'|'cuenta'|'desde'|'dia', v:'texto'}  ·  {k:'fecha', ge, lt}  ·  {k:'fecha', eq} */
  const CAMPO={tipo:'tipoL',cat:'cat',cuenta:'cuenta',desde:'desde',dia:'dia'};
  /* "=texto" para que no lo lea como >, < o fórmula; ~ protege * ? ~ (comodines de SUMAR.SI.CONJUNTO) */
  const crit=s=>'"='+String(s).replace(/[~*?]/g,'~$&').replace(/"/g,'""')+'"';
  const fDate=f=>{ const [y,m,d]=f.split('-').map(Number); return `DATE(${y},${m},${d})`; };
  const pares=c=>c.k==='fecha'
    ? (c.eq ? [`${M('fecha')},${fDate(c.eq)}`] : [`${M('fecha')},">="&${fDate(c.ge)}`,`${M('fecha')},"<"&${fDate(c.lt)}`])
    : [`${M(c.k==='tipo'?'tipo':c.k)},${crit(c.v)}`];
  const cumple=(r,c)=>c.k==='fecha'
    ? (c.eq ? r.fecha===c.eq : (r.fecha>=c.ge&&r.fecha<c.lt))
    : String(r[CAMPO[c.k]]).toLowerCase()===String(c.v).toLowerCase();
  const filtra=conds=>F.filter(r=>conds.every(c=>cumple(r,c)));
  const SUMA=conds=>({f:`SUMIFS(${M('monto')},${conds.flatMap(pares).join(',')})`,v:filtra(conds).reduce((a,r)=>a+r.monto,0)});
  const CUENTA=conds=>({f:`COUNTIFS(${conds.flatMap(pares).join(',')})`,v:filtra(conds).length});
  const sumO=(...xs)=>({f:xs.map(x=>x.f).join('+'),v:xs.reduce((a,x)=>a+x.v,0)});
  const T=t=>({k:'tipo',v:t});

  /* ---------- los meses y los días que cubre ---------- */
  const fechas=F.map(r=>r.fecha).sort();
  const f0=fechas[0], f1=fechas[fechas.length-1];
  const MESES=[];
  if(f0){
    let y=+f0.slice(0,4), m=+f0.slice(5,7); const yE=+f1.slice(0,4), mE=+f1.slice(5,7);
    while(y<yE||(y===yE&&m<=mE)){
      const ny=m===12?y+1:y, nm=m===12?1:m+1;
      MESES.push({y,m,lab:`${MES3[m-1]} ${y}`,ge:iso(y,m,1),lt:iso(ny,nm,1)});
      y=ny; m=nm;
    }
  }
  /* día a día: todo el rango pedido, pero sin días que todavía no llegan */
  const hoy=o.hoy||f1, dIni=o.desde||f0;
  const dFin=o.hasta?[o.hasta,f1>hoy?f1:hoy].sort()[0]:f1;
  const DIAS_R=[];
  if(dIni&&(fechaD(dFin)-fechaD(dIni))/864e5<=62){
    for(let d=fechaD(dIni);d<=fechaD(dFin);d.setDate(d.getDate()+1)){
      const f=iso(d.getFullYear(),d.getMonth()+1,d.getDate());
      DIAS_R.push({f,lab:`${DIAS[d.getDay()].slice(0,3)} ${d.getDate()} ${MES3[d.getMonth()]}`});
    }
  }

  const hojas=[];
  const nueva=(n,op)=>{ const h=new Hoja(n,op); hojas.push(h); return h; };

  /* ---------- encabezado de cada hoja de resumen ---------- */
  const encabezado=(h,titulo,nota)=>{
    h.txt(0,0,titulo,S.titulo); h.altos[0]=26;
    if(nota) h.txt(0,1,nota,S.nota);
  };
  /* fila de títulos de una tabla */
  const titulos=(h,r,lista)=>{ lista.forEach((t,i)=>h.txt(i,r,t,i===0?S.enc:S.encDer)); h.encs.add(r); };
  /* deja una gráfica debajo; devuelve la fila siguiente */
  const grafica=(h,fila,g)=>{ const alto=g.alto||16; h.graficas.push({...g,fila,alto}); return fila+alto+1; };

  /* ================= Resumen ================= */
  const res=nueva('Resumen');
  {
    const h=res;
    h.txt(0,0,limpio(o.app||'Mis finanzas'),S.titulo); h.altos[0]=26;
    h.txt(0,1,`Movimientos ${det?'con':'sin'} detalles · ${limpio(o.filtro||'todos')}`,S.subt);
    h.txt(0,2,`Descargado el ${limpio(o.generado||'')} · ${F.length} movimiento${F.length===1?'':'s'}`,S.nota);
    h.txt(0,3,'Las tablas y gráficas salen de la hoja Movimientos: si cambias un monto allá, se actualizan.'+
      (hayCuadre?' Los cuadres de saldo no cuentan como ingreso ni gasto.':''),S.nota);
    /* los números grandes */
    const K=[['Ingresos',SUMA([T('Ingreso')]),S.kpiPesos],['Gastos',SUMA([T('Gasto')]),S.kpiPesos]];
    K.push(['Neto (ingresos − gastos)',{f:`${REF(0,6)}-${REF(1,6)}`,v:K[0][1].v-K[1][1].v},S.kpiNeto]);
    if(hayP) K.push(['Pagos a tarjetas',SUMA([T('Pago a tarjeta')]),S.kpiPesos]);
    if(hayT) K.push(['Traslados',SUMA([T('Traslado')]),S.kpiPesos]);
    if(hayCuadre) K.push(['Cuadres (neto)',{f:`${SUMA([T('Cuadre (sube)')]).f}-${SUMA([T('Cuadre (baja)')]).f}`,
      v:SUMA([T('Cuadre (sube)')]).v-SUMA([T('Cuadre (baja)')]).v},S.kpiNeto]);
    K.push(['Movimientos',{f:`COUNTA(${M('fecha')})-1`,v:F.length},S.kpiEnt]);
    K.forEach(([l,x,s],i)=>{ h.txt(i,5,l,S.kpiLab); h.fx(i,6,x,s); });
    h.altos[5]=27; h.altos[6]=24;

    /* mes por mes */
    h.txt(0,8,'Mes por mes',S.seccion); h.altos[8]=20;
    const enc=['Mes','Ingresos','Gastos','Neto',...(hayP?['Pagos a tarjetas']:[]),...(hayT?['Traslados']:[]),'Movimientos'];
    titulos(h,9,enc);
    const r0=10;
    MESES.forEach((mm,i)=>{
      const r=r0+i, rg={k:'fecha',ge:mm.ge,lt:mm.lt};
      h.txt(0,r,mm.lab);
      const ing=SUMA([T('Ingreso'),rg]), gas=SUMA([T('Gasto'),rg]);
      h.fx(1,r,ing); h.fx(2,r,gas);
      h.fx(3,r,{f:`${REF(1,r)}-${REF(2,r)}`,v:ing.v-gas.v},S.neto);
      let c=4;
      if(hayP) h.fx(c++,r,SUMA([T('Pago a tarjeta'),rg]));
      if(hayT) h.fx(c++,r,SUMA([T('Traslado'),rg]));
      h.fx(c,r,CUENTA([rg]),S.ent);
    });
    const rt=r0+MESES.length;
    h.txt(0,rt,'Total',S.totTxt);
    for(let c=1;c<enc.length;c++){
      let v=0; for(let r=r0;r<rt;r++) v+=Number(h.val(c,r))||0;
      const s=c===enc.length-1?S.totEnt:(c===3?S.totNeto:S.totPesos);
      h.fx(c,rt,{f:`SUM(${REF(c,r0)}:${REF(c,rt-1)})`,v},s);
    }
    for(let c=0;c<Math.max(enc.length,K.length);c++) h.ancho(c,17);
    let fila=rt+2;
    fila=grafica(h,fila,{tipo:'barra',titulo:MESES.length>1?'Ingresos vs gastos, mes a mes':'Ingresos vs gastos',
      cat:{c:0,r1:r0,r2:rt-1},ser:[{nom:{c:1,r:9},val:{c:1,r1:r0,r2:rt-1},color:UP},{nom:{c:2,r:9},val:{c:2,r1:r0,r2:rt-1},color:DOWN}],
      leyenda:'b',etiquetas:MESES.length<=6?'val':null});
    if(MESES.length>1){
      const colores=MESES.map((_,i)=>(Number(h.val(3,r0+i))||0)<0?DOWN:UP);
      fila=grafica(h,fila,{tipo:'barra',titulo:'Neto de cada mes (lo que te quedó)',
        cat:{c:0,r1:r0,r2:rt-1},ser:[{nom:{c:3,r:9},val:{c:3,r1:r0,r2:rt-1},color:UP,colores}],etiquetas:MESES.length<=6?'val':null,fmt:FMT_PESOS});
    }
  }

  /* ================= Categorías (solo con detalles) ================= */
  const porCat=tipo=>{
    const m=new Map();
    F.filter(r=>r.tipoL===tipo).forEach(r=>{ const k=r.cat.toLowerCase(); const x=m.get(k)||{n:r.cat,v:0,c:0}; x.v+=r.monto; x.c++; m.set(k,x); });
    return [...m.values()].sort((a,b)=>b.v-a.v||a.n.localeCompare(b.n,'es'));
  };
  if(det&&(hayG||hayI)){
    const h=nueva('Categorías');
    encabezado(h,'Por categoría','De más a menos. Sale de la hoja Movimientos (solo gastos e ingresos; los pagos a tarjetas y traslados no tienen categoría).');
    h.ancho(0,26); h.ancho(1,15); h.ancho(2,11); h.ancho(3,13); h.ancho(4,14); h.ancho(5,3); h.ancho(6,24); h.ancho(7,15);
    let fila=3;
    const bloque=(tipo,titulo,tituloTorta,colorBarra)=>{
      const L=porCat(tipo); if(!L.length) return;
      h.txt(0,fila,titulo,S.seccion); h.altos[fila]=20; fila++;
      titulos(h,fila,['Categoría','Total','% del total','Movimientos','Promedio']);
      const r0=fila+1, rt=r0+L.length;
      const tot=L.reduce((a,x)=>a+x.v,0), cnt=L.reduce((a,x)=>a+x.c,0);
      L.forEach((x,i)=>{
        const r=r0+i;
        h.txt(0,r,x.n);
        h.fx(1,r,SUMA([T(tipo),{k:'cat',v:x.n}]));
        h.fx(2,r,{f:`IF(${ABS(1,rt)}=0,0,${REF(1,r)}/${ABS(1,rt)})`,v:tot?x.v/tot:0},S.pct);
        h.fx(3,r,CUENTA([T(tipo),{k:'cat',v:x.n}]),S.ent);
        h.fx(4,r,{f:`IF(${REF(3,r)}=0,0,${REF(1,r)}/${REF(3,r)})`,v:x.c?x.v/x.c:0});
      });
      h.txt(0,rt,'Total',S.totTxt);
      h.fx(1,rt,{f:`SUM(${REF(1,r0)}:${REF(1,rt-1)})`,v:tot},S.totPesos);
      h.fx(2,rt,{f:`IF(${REF(1,rt)}=0,0,1)`,v:tot?1:0},S.totPct);
      h.fx(3,rt,{f:`SUM(${REF(3,r0)}:${REF(3,rt-1)})`,v:cnt},S.totEnt);
      h.fx(4,rt,{f:`IF(${REF(3,rt)}=0,0,${REF(1,rt)}/${REF(3,rt)})`,v:cnt?tot/cnt:0},S.totPesos);
      /* torta: las 7 más grandes y "Otras" (al lado, para que la gráfica no quede llena de tajadas) */
      let cat={c:0,r1:r0,r2:rt-1}, val={c:1,r1:r0,r2:rt-1}, n=L.length;
      if(L.length>8){
        h.txt(6,fila,'Para la torta',S.enc); h.txt(7,fila,'Total',S.encDer);
        for(let i=0;i<7;i++){ h.fxs(6,r0+i,{f:REF(0,r0+i),v:L[i].n}); h.fx(7,r0+i,{f:REF(1,r0+i),v:L[i].v}); }
        const ro=r0+7, resto=L.slice(7).reduce((a,x)=>a+x.v,0);
        h.txt(6,ro,tipo==='Gasto'?'Otras':'Otros');
        h.fx(7,ro,{f:`${REF(1,rt)}-SUM(${REF(7,r0)}:${REF(7,ro-1)})`,v:resto});
        cat={c:6,r1:r0,r2:ro}; val={c:7,r1:r0,r2:ro}; n=8;
      }
      const colores=Array.from({length:n},(_,i)=>i===7&&L.length>8?GRIS:SERIE[i%SERIE.length]);
      fila=rt+2;
      fila=grafica(h,fila,{tipo:'torta',titulo:tituloTorta,cat,ser:[{nom:titulo,val,colores}],leyenda:'r'});
      fila=grafica(h,fila,{tipo:'barra',horizontal:true,titulo,cat:{c:0,r1:r0,r2:rt-1},
        ser:[{nom:{c:1,r:r0-1},val:{c:1,r1:r0,r2:rt-1},color:colorBarra}],etiquetas:'val',gap:45,
        alto:Math.max(12,Math.ceil(L.length*1.25)+4)});
    };
    bloque('Gasto','Gastos por categoría','¿En qué se fue la plata?',DOWN);
    bloque('Ingreso','Ingresos por categoría','¿De dónde entró la plata?',UP);
  }

  /* ================= Meses: comparación mes a mes por categoría (con detalles y 2 meses o más) ================= */
  if(det&&MESES.length>1&&(hayG||hayI)){
    const h=nueva('Meses');
    encabezado(h,'Comparación de meses','Cada fila es un mes; cada columna, una categoría. Sale de la hoja Movimientos.');
    let fila=3;
    const matriz=(tipo,titulo,max,otras)=>{
      const L=porCat(tipo); if(!L.length) return;
      const top=L.length>max+1?L.slice(0,max):L, conOtras=L.length>top.length;
      h.txt(0,fila,titulo,S.seccion); h.altos[fila]=20; fila++;
      const enc=['Mes',...top.map(x=>x.n),...(conOtras?[otras]:[]),'Total'];
      titulos(h,fila,enc);
      const r0=fila+1, rt=r0+MESES.length, cT=enc.length-1;
      MESES.forEach((mm,i)=>{
        const r=r0+i, rg={k:'fecha',ge:mm.ge,lt:mm.lt};
        h.txt(0,r,mm.lab);
        let suma=0;
        top.forEach((x,j)=>{ const s=SUMA([T(tipo),{k:'cat',v:x.n},rg]); suma+=s.v; h.fx(1+j,r,s); });
        const tot=SUMA([T(tipo),rg]);
        if(conOtras) h.fx(cT-1,r,{f:`${REF(cT,r)}-SUM(${REF(1,r)}:${REF(cT-2,r)})`,v:tot.v-suma});
        h.fx(cT,r,tot);
      });
      h.txt(0,rt,'Total',S.totTxt);
      for(let c=1;c<=cT;c++){ let v=0; for(let r=r0;r<rt;r++) v+=Number(h.val(c,r))||0;
        h.fx(c,rt,{f:`SUM(${REF(c,r0)}:${REF(c,rt-1)})`,v},S.totPesos); }
      const ns=cT-1;
      fila=rt+2;
      fila=grafica(h,fila,{tipo:'barra',apilado:true,titulo:`${titulo}, mes a mes`,cat:{c:0,r1:r0,r2:rt-1},
        ser:Array.from({length:ns},(_,j)=>({nom:{c:1+j,r:r0-1},val:{c:1+j,r1:r0,r2:rt-1},
          color:conOtras&&j===ns-1?GRIS:SERIE[j%SERIE.length]})),leyenda:'b',gap:55,alto:18});
    };
    matriz('Gasto','Gastos por categoría',7,'Otras');
    matriz('Ingreso','Ingresos por categoría',5,'Otros');
    h.ancho(0,13); for(let c=1;c<=9;c++) h.ancho(c,15);
  }

  /* ================= Cuentas y días ================= */
  {
    const h=nueva('Cuentas y días');
    encabezado(h,'Por cuenta o tarjeta','Sale de la hoja Movimientos. Un traslado sale de una cuenta y entra a otra; un pago a la tarjeta sale de una cuenta y baja la deuda de la tarjeta.');
    let fila=3;
    const orden=(o.cuentas||[]).map(limpio);
    const vistas=new Map();
    F.forEach(r=>[r.cuenta,r.desde].forEach(n=>{ if(n&&n!=='Otra cuenta'&&!vistas.has(n.toLowerCase())) vistas.set(n.toLowerCase(),n); }));
    const ctas=[...vistas.values()].sort((a,b)=>{
      const ia=orden.findIndex(x=>x.toLowerCase()===a.toLowerCase()), ib=orden.findIndex(x=>x.toLowerCase()===b.toLowerCase());
      return (ia<0?99:ia)-(ib<0?99:ib)||a.localeCompare(b,'es'); });
    const enc=['Cuenta o tarjeta','Ingresos','Gastos',...(hayT?['Traslados (entraron)','Traslados (salieron)']:[]),...(hayP?['Pagos a tarjeta']:[]),'Movimientos'];
    titulos(h,fila,enc);
    const r0=fila+1;
    ctas.forEach((n,i)=>{
      const r=r0+i, C={k:'cuenta',v:n}, D={k:'desde',v:n};
      h.txt(0,r,n);
      h.fx(1,r,SUMA([T('Ingreso'),C])); h.fx(2,r,SUMA([T('Gasto'),C]));
      let c=3;
      if(hayT){ h.fx(c++,r,SUMA([T('Traslado'),C])); h.fx(c++,r,SUMA([T('Traslado'),D])); }
      if(hayP) h.fx(c++,r,sumO(SUMA([T('Pago a tarjeta'),C]),SUMA([T('Pago a tarjeta'),D])));
      h.fx(c,r,CI.desde!=null?sumO(CUENTA([C]),CUENTA([D])):CUENTA([C]),S.ent);
    });
    const rt=r0+ctas.length;
    h.ancho(0,22); for(let c=1;c<enc.length;c++) h.ancho(c,15);
    fila=rt+1;
    if(ctas.length) fila=grafica(h,fila,{tipo:'barra',titulo:'Ingresos y gastos por cuenta',cat:{c:0,r1:r0,r2:rt-1},
      ser:[{nom:{c:1,r:r0-1},val:{c:1,r1:r0,r2:rt-1},color:UP},{nom:{c:2,r:r0-1},val:{c:2,r1:r0,r2:rt-1},color:DOWN}],
      leyenda:'b',etiquetas:ctas.length<=6?'val':null,alto:15});

    /* día de la semana */
    h.txt(0,fila,'Por día de la semana',S.seccion); h.altos[fila]=20; fila++;
    titulos(h,fila,['Día','Gastos','Ingresos','Cuántos gastos']);
    const d0=fila+1;
    ORDEN_DIAS.forEach((d,i)=>{
      const r=d0+i, D={k:'dia',v:d};
      h.txt(0,r,d.charAt(0).toUpperCase()+d.slice(1));
      h.fx(1,r,SUMA([T('Gasto'),D])); h.fx(2,r,SUMA([T('Ingreso'),D])); h.fx(3,r,CUENTA([T('Gasto'),D]),S.ent);
    });
    fila=d0+7+1;
    fila=grafica(h,fila,{tipo:'barra',titulo:'¿Qué días gastas más?',cat:{c:0,r1:d0,r2:d0+6},
      ser:[{nom:{c:1,r:d0-1},val:{c:1,r1:d0,r2:d0+6},color:SERIE[0]}],etiquetas:'val',alto:14});

    /* los gastos más grandes (con detalles): es una foto del momento de la descarga */
    if(det&&hayG){
      h.txt(0,fila,'Los 10 gastos más grandes',S.seccion); h.altos[fila]=20; fila++;
      h.txt(0,fila,'Esta lista es fija: es como estaba al descargar.',S.nota); fila++;
      titulos(h,fila,['Fecha','Monto','Categoría','Cuenta o tarjeta','Descripción']);
      F.filter(r=>r.tipoL==='Gasto').sort((a,b)=>b.monto-a.monto||(a.fecha<b.fecha?1:-1)).slice(0,10).forEach((r,i)=>{
        const rr=fila+1+i;
        h.num(0,rr,serial(r.fecha),S.fecha); h.num(1,rr,r.monto); h.txt(2,rr,r.cat); h.txt(3,rr,r.cuenta); h.txt(4,rr,limpio(r.nota||''));
      });
    }
  }

  /* ================= Día a día (cuando son dos meses o menos) ================= */
  if(DIAS_R.length){
    const h=nueva('Día a día');
    encabezado(h,'Día a día','Sale de la hoja Movimientos.');
    titulos(h,3,['Día','Ingresos','Gastos','Gastos acumulados']);
    const r0=4;
    DIAS_R.forEach((d,i)=>{
      const r=r0+i, D={k:'fecha',eq:d.f};
      h.txt(0,r,d.lab);
      const ing=SUMA([T('Ingreso'),D]), gas=SUMA([T('Gasto'),D]);
      h.fx(1,r,ing); h.fx(2,r,gas);
      const prev=i?Number(h.val(3,r-1))||0:0;
      h.fx(3,r,{f:i?`${REF(3,r-1)}+${REF(2,r)}`:REF(2,r),v:prev+gas.v});
    });
    const rt=r0+DIAS_R.length;
    h.txt(0,rt,'Total',S.totTxt);
    [1,2].forEach(c=>{ let v=0; for(let r=r0;r<rt;r++) v+=Number(h.val(c,r))||0; h.fx(c,rt,{f:`SUM(${REF(c,r0)}:${REF(c,rt-1)})`,v},S.totPesos); });
    h.ancho(0,13); h.ancho(1,15); h.ancho(2,15); h.ancho(3,19);
    let fila=rt+2;
    fila=grafica(h,fila,{tipo:'barra',titulo:'Ingresos y gastos de cada día',cat:{c:0,r1:r0,r2:rt-1},
      ser:[{nom:{c:1,r:3},val:{c:1,r1:r0,r2:rt-1},color:UP},{nom:{c:2,r:3},val:{c:2,r1:r0,r2:rt-1},color:DOWN}],leyenda:'b',gap:40});
    fila=grafica(h,fila,{tipo:'linea',titulo:'Cómo se fue sumando el gasto',cat:{c:0,r1:r0,r2:rt-1},
      ser:[{nom:{c:3,r:3},val:{c:3,r1:r0,r2:rt-1},color:DOWN,grueso:true}]});
  }

  /* ================= Plata por mes (toda la plata, no depende de los filtros) ================= */
  const P=(o.plata||[]).filter(x=>x&&x.mes);
  if(P.length){
    const h=nueva('Plata por mes');
    encabezado(h,'Plata por mes','Toda tu plata junta (las cuentas, sin las tarjetas), con lo anotado y lo de los extractos. No depende de los filtros: solo de los meses.');
    titulos(h,3,['Mes','Cerró con','Máximo','Día del máximo','Mínimo','Promedio']);
    const r0=4;
    P.forEach((x,i)=>{
      const r=r0+i, [y,m]=x.mes.split('-').map(Number);
      h.txt(0,r,`${MES3[m-1]} ${y}`);
      h.num(1,r,x.fin); h.num(2,r,x.max);
      if(x.diaMax) h.num(3,r,serial(x.diaMax),S.fecha); else h.txt(3,r,'');
      h.num(4,r,x.min); h.num(5,r,x.prom);
    });
    const rt=r0+P.length;
    h.ancho(0,13); for(let c=1;c<=5;c++) h.ancho(c,15);
    if(P.length>1) grafica(h,rt+1,{tipo:'linea',suave:true,titulo:'Cómo se movió tu plata',cat:{c:0,r1:r0,r2:rt-1},
      ser:[{nom:{c:1,r:3},val:{c:1,r1:r0,r2:rt-1},color:COLOR,grueso:true,puntos:P.length<=24},
           {nom:{c:2,r:3},val:{c:2,r1:r0,r2:rt-1},color:UP,punteada:true},
           {nom:{c:4,r:3},val:{c:4,r1:r0,r2:rt-1},color:DOWN,punteada:true}],leyenda:'b'});
  }

  /* ================= Movimientos (la tabla con todo) ================= */
  {
    const h=nueva(MOV,{cuadricula:true});
    h.congelar=true;
    COLS.forEach((c,i)=>{ h.txt(i,0,c.h,c.n?S.encDer:S.enc); h.ancho(i,c.w); });
    const orden=F.slice().sort((a,b)=>a.fecha<b.fecha?-1:a.fecha>b.fecha?1:String(a.creado||'').localeCompare(String(b.creado||'')));
    orden.forEach((r,i)=>{
      const rr=i+1;
      COLS.forEach((c,j)=>{
        const v=c.v(r);
        if(c.k==='fecha') h.num(j,rr,serial(v),S.fecha);
        else if(c.k==='monto') h.num(j,rr,v,r.tipoL==='Ingreso'?S.pesosUp:(r.tipoL==='Gasto'?S.pesosDown:S.pesos));
        else if(c.n){ if(v!=null) h.num(j,rr,v,c.s); }
        else if(v) h.txt(j,rr,v,S.txt);
      });
    });
    h.tabla={nombre:'TablaMovimientos',ref:`A1:${REF(COLS.length-1,Math.max(1,orden.length))}`,cols:COLS.map(c=>c.h)};
    /* una tabla de Excel necesita al menos una fila de datos */
    if(!orden.length) h.txt(0,1,'');
  }

  /* las hojas en este orden; Movimientos siempre al final */
  return empacar(hojas,{titulo:`Movimientos ${det?'con':'sin'} detalles`,app:o.app,COLOR});
}

/* ================= XML de las hojas ================= */
const NS_S='http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const NS_R='http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const NS_C='http://schemas.openxmlformats.org/drawingml/2006/chart';
const NS_A='http://schemas.openxmlformats.org/drawingml/2006/main';
const NS_X='http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing';
const NS_PR='http://schemas.openxmlformats.org/package/2006/relationships';
const CAB='<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const RT={hoja:'http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet',
  estilos:'http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles',
  textos:'http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings',
  dibujo:'http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing',
  grafica:'http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart',
  tabla:'http://schemas.openxmlformats.org/officeDocument/2006/relationships/table',
  doc:'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
  core:'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties',
  app:'http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties'};
const CT={hoja:'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml',
  libro:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
  estilos:'application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml',
  textos:'application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml',
  dibujo:'application/vnd.openxmlformats-officedocument.drawing+xml',
  grafica:'application/vnd.openxmlformats-officedocument.drawingml.chart+xml',
  tabla:'application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml',
  core:'application/vnd.openxmlformats-package.core-properties+xml',
  app:'application/vnd.openxmlformats-officedocument.extended-properties+xml'};
const rels=l=>CAB+`<Relationships xmlns="${NS_PR}">`+l.map(([id,t,dst])=>`<Relationship Id="${id}" Type="${t}" Target="${XE(dst)}"/>`).join('')+'</Relationships>';

class Textos{
  constructor(){ this.m=new Map(); this.l=[]; this.n=0; }
  i(s){ this.n++; let k=this.m.get(s); if(k===undefined){ k=this.l.length; this.l.push(s); this.m.set(s,k); } return k; }
  xml(){ return CAB+`<sst xmlns="${NS_S}" count="${this.n}" uniqueCount="${this.l.length}">`+
    this.l.map(s=>`<si><t${/^\s|\s$|\n/.test(s)?' xml:space="preserve"':''}>${XE(s)}</t></si>`).join('')+'</sst>'; }
}

function hojaXml(h,tx,esPrimera,relDib,relTabla){
  const filas=[...h.c.keys()].sort((a,b)=>a-b);
  /* una fila de títulos más alta si algún título no cabe en su columna */
  h.encs.forEach(r=>{ if(h.altos[r]) return;
    for(const [c,x] of h.c.get(r)) if(String(x.v).length*1.15+1>(h.anchos[c]??8.43)){ h.altos[r]=27; break; } });
  let sd='';
  for(const r of filas){
    const cs=[...h.c.get(r).entries()].sort((a,b)=>a[0]-b[0]);
    const alto=h.altos[r]?` ht="${h.altos[r]}" customHeight="1"`:'';
    sd+=`<row r="${r+1}"${alto}>`;
    for(const [c,x] of cs){
      const ref=REF(c,r), s=x.s?` s="${x.s}"`:'';
      if(x.t==='s'){ sd+= x.v==='' ? `<c r="${ref}"${s}/>` : `<c r="${ref}"${s} t="s"><v>${tx.i(x.v)}</v></c>`; }
      else if(x.t==='n') sd+=`<c r="${ref}"${s}><v>${numX(x.v)}</v></c>`;
      else if(x.t==='fs') sd+=`<c r="${ref}"${s} t="str"><f>${XE(x.f)}</f><v>${XE(x.v)}</v></c>`;
      else sd+=`<c r="${ref}"${s}><f>${XE(x.f)}</f><v>${numX(x.v)}</v></c>`;
    }
    sd+='</row>';
  }
  const cols=Object.keys(h.anchos).map(Number).sort((a,b)=>a-b)
    .map(c=>`<col min="${c+1}" max="${c+1}" width="${h.anchos[c]}" customWidth="1"/>`).join('');
  const pane=h.congelar?'<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/>':'<selection activeCell="A1" sqref="A1"/>';
  return CAB+`<worksheet xmlns="${NS_S}" xmlns:r="${NS_R}">`+
    `<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>`+
    `<dimension ref="A1:${REF(Math.max(h.maxC,0),Math.max(h.maxR,0))}"/>`+
    `<sheetViews><sheetView workbookViewId="0"${h.cuadricula?'':' showGridLines="0"'}${esPrimera?' tabSelected="1"':''}>${pane}</sheetView></sheetViews>`+
    `<sheetFormatPr defaultRowHeight="15" customHeight="1"/>`+
    (cols?`<cols>${cols}</cols>`:'')+
    `<sheetData>${sd}</sheetData>`+
    `<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>`+
    `<pageSetup orientation="${h.tabla?'landscape':'portrait'}" fitToWidth="1" fitToHeight="0"/>`+
    (relDib?`<drawing r:id="${relDib}"/>`:'')+
    (relTabla?`<tableParts count="1"><tablePart r:id="${relTabla}"/></tableParts>`:'')+
    '</worksheet>';
}

function tablaXml(t,id){
  return CAB+`<table xmlns="${NS_S}" id="${id}" name="${t.nombre}" displayName="${t.nombre}" ref="${t.ref}" totalsRowShown="0">`+
    `<autoFilter ref="${t.ref}"/><tableColumns count="${t.cols.length}">`+
    t.cols.map((c,i)=>`<tableColumn id="${i+1}" name="${XE(c)}"/>`).join('')+
    `</tableColumns><tableStyleInfo name="TableStyleLight1" showFirstColumn="0" showLastColumn="0" showRowStripes="1" showColumnStripes="0"/></table>`;
}

/* ---------- estilos ---------- */
function estilosXml(COLOR){
  const fuentes=[
    [10,'1F2328',0],[10,'1F2328',1],[10,'FFFFFF',1],[18,COLOR,1],[9,'6B7280',0],[14,'1F2328',1],[12,COLOR,1],[9,'4B5563',1],
    [10,'047857',0],[10,'BE123C',0],[11,'374151',1]
  ].map(([sz,c,b])=>`<font>${b?'<b/>':''}<sz val="${sz}"/><color rgb="FF${c}"/><name val="Arial"/><family val="2"/></font>`);
  const rellenos=['<fill><patternFill patternType="none"/></fill>','<fill><patternFill patternType="gray125"/></fill>',
    `<fill><patternFill patternType="solid"><fgColor rgb="FF${COLOR}"/><bgColor indexed="64"/></patternFill></fill>`,
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF3F4F6"/><bgColor indexed="64"/></patternFill></fill>'];
  const bordes=['<border><left/><right/><top/><bottom/><diagonal/></border>',
    '<border><left/><right/><top/><bottom style="thin"><color rgb="FFE5E7EB"/></bottom><diagonal/></border>',
    '<border><left/><right/><top style="thin"><color rgb="FF9CA3AF"/></top><bottom/><diagonal/></border>'];
  /* [numFmt, fuente, relleno, borde, alineación] — en el orden de S */
  const xf=[
    [0,0,0,0,''],                                   // base
    [0,3,0,0,''],                                   // titulo
    [0,4,0,0,''],                                   // nota
    [0,2,2,0,'<alignment vertical="center" wrapText="1"/>'],     // enc
    [0,0,0,1,''],                                   // txt
    [164,0,0,1,'<alignment horizontal="left"/>'],   // fecha
    [165,0,0,1,''],                                 // pesos
    [166,0,0,1,''],                                 // neto
    [167,0,0,1,''],                                 // pct
    [3,0,0,1,''],                                   // ent
    [0,1,3,2,''],                                   // totTxt
    [165,1,3,2,''],                                 // totPesos
    [166,1,3,2,''],                                 // totNeto
    [3,1,3,2,''],                                   // totEnt
    [167,1,3,2,''],                                 // totPct
    [0,6,0,0,''],                                   // seccion
    [0,7,3,0,'<alignment vertical="center" wrapText="1"/>'], // kpiLab
    [165,5,3,0,'<alignment vertical="center"/>'],   // kpiPesos
    [166,5,3,0,'<alignment vertical="center"/>'],   // kpiNeto
    [3,5,3,0,'<alignment vertical="center"/>'],     // kpiEnt
    [0,2,2,0,'<alignment horizontal="right" vertical="center" wrapText="1"/>'], // encDer
    [165,8,0,1,''],                                 // pesosUp
    [165,9,0,1,''],                                 // pesosDown
    [0,10,0,0,'']                                   // subt
  ].map(([n,f,fi,b,al])=>`<xf numFmtId="${n}" fontId="${f}" fillId="${fi}" borderId="${b}" xfId="0"${n?' applyNumberFormat="1"':''} applyFont="1"${fi?' applyFill="1"':''}${b?' applyBorder="1"':''}${al?' applyAlignment="1">'+al+'</xf>':'/>'}`);
  return CAB+`<styleSheet xmlns="${NS_S}">`+
    `<numFmts count="4"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="${XE(FMT_PESOS)}"/>`+
    `<numFmt numFmtId="166" formatCode="${XE(FMT_PESOS+';[Red]-'+FMT_PESOS)}"/><numFmt numFmtId="167" formatCode="0.0%"/></numFmts>`+
    `<fonts count="${fuentes.length}">${fuentes.join('')}</fonts>`+
    `<fills count="${rellenos.length}">${rellenos.join('')}</fills>`+
    `<borders count="${bordes.length}">${bordes.join('')}</borders>`+
    `<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>`+
    `<cellXfs count="${xf.length}">${xf.join('')}</cellXfs>`+
    `<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>`+
    `<dxfs count="0"/><tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/></styleSheet>`;
}

/* ================= gráficas ================= */
const relleno=c=>`<a:solidFill><a:srgbClr val="${hex(c)}"/></a:solidFill>`;
const rpr=(sz,c,b)=>`sz="${sz}" b="${b?1:0}">${relleno(c)}<a:latin typeface="Arial"/><a:cs typeface="Arial"/>`;
const txPr=(sz,c,b)=>`<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr ${rpr(sz,c,b)}</a:defRPr></a:pPr><a:endParaRPr lang="es-CO"/></a:p></c:txPr>`;
const sinBorde='<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>';
const tituloXml=t=>`<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr ${rpr(1200,'1F2328',1)}</a:defRPr></a:pPr>`+
  `<a:r><a:rPr lang="es-CO" ${rpr(1200,'1F2328',1)}</a:rPr><a:t>${XE(t)}</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title>`;
const rango=(h,c,a,b)=>`${HQ(h.n)}!${ABS(c,a)}${b>a?':'+ABS(c,b):''}`;
function strRef(h,c,a,b){
  const v=[]; for(let r=a;r<=b;r++) v.push(String(h.val(c,r)??''));
  return `<c:strRef><c:f>${XE(rango(h,c,a,b))}</c:f><c:strCache><c:ptCount val="${v.length}"/>`+
    v.map((x,i)=>`<c:pt idx="${i}"><c:v>${XE(x)}</c:v></c:pt>`).join('')+'</c:strCache></c:strRef>';
}
function numRef(h,c,a,b){
  const v=[]; for(let r=a;r<=b;r++) v.push(Number(h.val(c,r))||0);
  return `<c:numRef><c:f>${XE(rango(h,c,a,b))}</c:f><c:numCache><c:formatCode>${XE(FMT_PESOS)}</c:formatCode><c:ptCount val="${v.length}"/>`+
    v.map((x,i)=>`<c:pt idx="${i}"><c:v>${numX(x)}</c:v></c:pt>`).join('')+'</c:numCache></c:numRef>';
}
const serTx=(s,h)=>typeof s.nom==='object'?`<c:tx>${strRef(h,s.nom.c,s.nom.r,s.nom.r)}</c:tx>`:`<c:tx><c:v>${XE(s.nom)}</c:v></c:tx>`;
const catVal=(g,s,h)=>`<c:cat>${strRef(h,g.cat.c,g.cat.r1,g.cat.r2)}</c:cat><c:val>${numRef(h,s.val.c,s.val.r1,s.val.r2)}</c:val>`;
const etiquetasVal=(pos,fmt)=>`<c:dLbls><c:numFmt formatCode="${XE(fmt||FMT_K)}" sourceLinked="0"/>${sinBorde}${txPr(800,'374151',0)}`+
  `${pos?`<c:dLblPos val="${pos}"/>`:''}<c:showLegendKey val="0"/><c:showVal val="1"/><c:showCatName val="0"/><c:showSerName val="0"/><c:showPercent val="0"/><c:showBubbleSize val="0"/></c:dLbls>`;
function ejes(g){
  const hz=!!g.horizontal;
  return `<c:catAx><c:axId val="5001"/><c:scaling><c:orientation val="${hz?'maxMin':'minMax'}"/></c:scaling><c:delete val="0"/>`+
    `<c:axPos val="${hz?'l':'b'}"/><c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/>`+
    `<c:tickLblPos val="low"/><c:spPr><a:ln w="9525">${relleno('C4C8CE')}</a:ln></c:spPr>${txPr(900,'4B5563',0)}`+
    `<c:crossAx val="5002"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>`+
    `<c:valAx><c:axId val="5002"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="${hz?'b':'l'}"/>`+
    `<c:majorGridlines><c:spPr><a:ln w="6350">${relleno('E5E7EB')}</a:ln></c:spPr></c:majorGridlines>`+
    `<c:numFmt formatCode="${XE(g.fmt||FMT_K)}" sourceLinked="0"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>`+
    `<c:spPr><a:ln><a:noFill/></a:ln></c:spPr>${txPr(900,'4B5563',0)}<c:crossAx val="5001"/><c:crosses val="${hz?'max':'autoZero'}"/><c:crossBetween val="between"/></c:valAx>`;
}
function barras(g,h){
  const sers=g.ser.map((s,i)=>`<c:ser><c:idx val="${i}"/><c:order val="${i}"/>${serTx(s,h)}<c:spPr>${relleno(s.color)}</c:spPr><c:invertIfNegative val="0"/>`+
    (s.colores||[]).map((c,j)=>`<c:dPt><c:idx val="${j}"/><c:invertIfNegative val="0"/><c:bubble3D val="0"/><c:spPr>${relleno(c)}</c:spPr></c:dPt>`).join('')+
    (g.etiquetas==='val'?etiquetasVal(g.apilado?null:'outEnd',g.fmt):'')+catVal(g,s,h)+'</c:ser>').join('');
  return `<c:barChart><c:barDir val="${g.horizontal?'bar':'col'}"/><c:grouping val="${g.apilado?'stacked':'clustered'}"/><c:varyColors val="0"/>${sers}`+
    `<c:gapWidth val="${g.gap||70}"/>${g.apilado?'<c:overlap val="100"/>':(g.ser.length>1?'<c:overlap val="-8"/>':'')}<c:axId val="5001"/><c:axId val="5002"/></c:barChart>`+ejes(g);
}
function lineas(g,h){
  const sers=g.ser.map((s,i)=>`<c:ser><c:idx val="${i}"/><c:order val="${i}"/>${serTx(s,h)}`+
    `<c:spPr><a:ln w="${s.grueso?31750:15875}" cap="rnd">${relleno(s.color)}${s.punteada?'<a:prstDash val="dash"/>':''}<a:round/></a:ln></c:spPr>`+
    `<c:marker><c:symbol val="${s.puntos?'circle':'none'}"/>${s.puntos?`<c:size val="5"/><c:spPr>${relleno(s.color)}<a:ln w="9525">${relleno('FFFFFF')}</a:ln></c:spPr>`:''}</c:marker>`+
    catVal(g,s,h)+`<c:smooth val="${g.suave?1:0}"/></c:ser>`).join('');
  return `<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>${sers}<c:marker val="1"/><c:axId val="5001"/><c:axId val="5002"/></c:lineChart>`+ejes(g);
}
function torta(g,h){
  const s=g.ser[0], n=g.cat.r2-g.cat.r1+1;
  const vals=[]; for(let r=s.val.r1;r<=s.val.r2;r++) vals.push(Number(h.val(s.val.c,r))||0);
  const tot=vals.reduce((a,b)=>a+b,0);
  const pts=Array.from({length:n},(_,j)=>`<c:dPt><c:idx val="${j}"/><c:bubble3D val="0"/><c:spPr>${relleno(s.colores[j%s.colores.length])}<a:ln w="12700">${relleno('FFFFFF')}</a:ln></c:spPr></c:dPt>`).join('');
  /* sin el % en las tajadas muy chiquitas (no cabe) */
  const ocultas=vals.map((v,j)=>tot&&v/tot<0.035?`<c:dLbl><c:idx val="${j}"/><c:delete val="1"/></c:dLbl>`:'').join('');
  const lbl=`<c:dLbls>${ocultas}<c:numFmt formatCode="0%" sourceLinked="0"/>${sinBorde}${txPr(900,'1F2328',1)}<c:dLblPos val="outEnd"/>`+
    `<c:showLegendKey val="0"/><c:showVal val="0"/><c:showCatName val="0"/><c:showSerName val="0"/><c:showPercent val="1"/><c:showBubbleSize val="0"/><c:showLeaderLines val="1"/></c:dLbls>`;
  return `<c:pieChart><c:varyColors val="1"/><c:ser><c:idx val="0"/><c:order val="0"/>${serTx(s,h)}${pts}${lbl}${catVal(g,s,h)}</c:ser><c:firstSliceAng val="0"/></c:pieChart>`;
}
function graficaXml(g,h){
  const plot=g.tipo==='linea'?lineas(g,h):(g.tipo==='torta'?torta(g,h):barras(g,h));
  const ley=g.leyenda?`<c:legend><c:legendPos val="${g.leyenda}"/><c:overlay val="0"/>${txPr(900,'374151',0)}</c:legend>`:'';
  return CAB+`<c:chartSpace xmlns:c="${NS_C}" xmlns:a="${NS_A}" xmlns:r="${NS_R}"><c:date1904 val="0"/><c:lang val="es-CO"/><c:roundedCorners val="0"/>`+
    `<c:chart>${tituloXml(g.titulo)}<c:autoTitleDeleted val="0"/><c:plotArea><c:layout/>${plot}${sinBorde}</c:plotArea>${ley}`+
    `<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>`+
    `<c:spPr>${relleno('FFFFFF')}<a:ln w="9525">${relleno('E5E7EB')}</a:ln></c:spPr>${txPr(900,'374151',0)}</c:chartSpace>`;
}
/* hasta qué columna llega una gráfica de ~640 px de ancho */
function hastaCol(h,c0,px){
  let c=c0, usado=0;
  for(;;){ const w=h.anchos[c]??8.43, p=Math.trunc(w*7+5);
    if(usado+p>=px) return [c,Math.round((px-usado)*9525)];
    usado+=p; c++; }
}
function dibujoXml(h){
  return CAB+`<xdr:wsDr xmlns:xdr="${NS_X}" xmlns:a="${NS_A}">`+h.graficas.map((g,i)=>{
    const [c2,off]=hastaCol(h,0,g.ancho||640);
    return `<xdr:twoCellAnchor editAs="oneCell"><xdr:from><xdr:col>0</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${g.fila}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>`+
      `<xdr:to><xdr:col>${c2}</xdr:col><xdr:colOff>${off}</xdr:colOff><xdr:row>${g.fila+g.alto}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>`+
      `<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="${i+2}" name="${XE(g.titulo)}"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>`+
      `<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="${NS_C}">`+
      `<c:chart xmlns:c="${NS_C}" xmlns:r="${NS_R}" r:id="rId${i+1}"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>`;
  }).join('')+'</xdr:wsDr>';
}

/* ================= el paquete .xlsx ================= */
async function empacar(hojas,{titulo,app,COLOR}){
  const tx=new Textos(), archivos=[], tipos=[];
  let nG=0, nD=0, nT=0;
  const libroRels=[];
  hojas.forEach((h,i)=>{
    const n=i+1, rl=[]; let relDib=null, relTabla=null;
    if(h.graficas.length){
      nD++; relDib='rId1'; rl.push([relDib,RT.dibujo,`../drawings/drawing${nD}.xml`]);
      const dr=[];
      h.graficas.forEach((g,j)=>{ nG++;
        archivos.push([`xl/charts/chart${nG}.xml`,graficaXml(g,h)]); tipos.push([`/xl/charts/chart${nG}.xml`,CT.grafica]);
        dr.push([`rId${j+1}`,RT.grafica,`../charts/chart${nG}.xml`]); });
      archivos.push([`xl/drawings/drawing${nD}.xml`,dibujoXml(h)]); tipos.push([`/xl/drawings/drawing${nD}.xml`,CT.dibujo]);
      archivos.push([`xl/drawings/_rels/drawing${nD}.xml.rels`,rels(dr)]);
    }
    if(h.tabla){
      nT++; relTabla=`rId${rl.length+1}`; rl.push([relTabla,RT.tabla,`../tables/table${nT}.xml`]);
      archivos.push([`xl/tables/table${nT}.xml`,tablaXml(h.tabla,nT)]); tipos.push([`/xl/tables/table${nT}.xml`,CT.tabla]);
    }
    archivos.push([`xl/worksheets/sheet${n}.xml`,hojaXml(h,tx,i===0,relDib,relTabla)]); tipos.push([`/xl/worksheets/sheet${n}.xml`,CT.hoja]);
    if(rl.length) archivos.push([`xl/worksheets/_rels/sheet${n}.xml.rels`,rels(rl)]);
    libroRels.push([`rId${n}`,RT.hoja,`worksheets/sheet${n}.xml`]);
  });
  const k=hojas.length;
  libroRels.push([`rId${k+1}`,RT.estilos,'styles.xml'],[`rId${k+2}`,RT.textos,'sharedStrings.xml']);
  const libro=CAB+`<workbook xmlns="${NS_S}" xmlns:r="${NS_R}"><bookViews><workbookView activeTab="0"/></bookViews><sheets>`+
    hojas.map((h,i)=>`<sheet name="${XE(h.n)}" sheetId="${i+1}" r:id="rId${i+1}"/>`).join('')+
    `</sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>`;
  const ahora=new Date().toISOString().replace(/\.\d+Z$/,'Z');
  const core=CAB+`<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">`+
    `<dc:title>${XE(limpio(titulo))}</dc:title><dc:creator>${XE(limpio(app||'Finanzas'))}</dc:creator>`+
    `<dcterms:created xsi:type="dcterms:W3CDTF">${ahora}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${ahora}</dcterms:modified></cp:coreProperties>`;
  const appx=CAB+`<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>${XE(limpio(app||'Finanzas'))}</Application></Properties>`;
  /* los textos se cuentan al escribir las hojas: va después de ellas */
  const todo=[
    ['[Content_Types].xml',null],
    ['_rels/.rels',rels([['rId1',RT.doc,'xl/workbook.xml'],['rId2',RT.core,'docProps/core.xml'],['rId3',RT.app,'docProps/app.xml']])],
    ['docProps/core.xml',core],['docProps/app.xml',appx],
    ['xl/workbook.xml',libro],['xl/_rels/workbook.xml.rels',rels(libroRels)],
    ['xl/styles.xml',estilosXml(COLOR)],
    ...archivos,
    ['xl/sharedStrings.xml',tx.xml()]
  ];
  tipos.push(['/xl/workbook.xml',CT.libro],['/xl/styles.xml',CT.estilos],['/xl/sharedStrings.xml',CT.textos],
    ['/docProps/core.xml',CT.core],['/docProps/app.xml',CT.app]);
  todo[0][1]=CAB+`<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">`+
    `<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>`+
    tipos.map(([p,t])=>`<Override PartName="${p}" ContentType="${t}"/>`).join('')+'</Types>';
  return zip(todo);
}

/* ================= ZIP (deflate del navegador si lo tiene; si no, sin comprimir) ================= */
const CRC=(()=>{ const t=new Uint32Array(256); for(let n=0;n<256;n++){ let c=n; for(let k=0;k<8;k++) c=c&1?0xEDB88320^(c>>>1):c>>>1; t[n]=c>>>0; } return t; })();
function crc32(u){ let c=0xFFFFFFFF; for(let i=0;i<u.length;i++) c=CRC[(c^u[i])&255]^(c>>>8); return (c^0xFFFFFFFF)>>>0; }
async function comprimir(u){
  if(typeof CompressionStream==='undefined') return null;
  try{ const s=new Blob([u]).stream().pipeThrough(new CompressionStream('deflate-raw'));
       return new Uint8Array(await new Response(s).arrayBuffer()); }
  catch(e){ return null; }
}
async function zip(lista){
  const enc=new TextEncoder(), partes=[], central=[]; let off=0;
  const d=new Date(), hora=(d.getHours()<<11)|(d.getMinutes()<<5)|(d.getSeconds()>>1),
        dia=((d.getFullYear()-1980)<<9)|((d.getMonth()+1)<<5)|d.getDate();
  for(const [nombre,txt] of lista){
    const nm=enc.encode(nombre), raw=enc.encode(txt), crc=crc32(raw);
    let datos=await comprimir(raw), met=8;
    if(!datos||datos.length>=raw.length){ datos=raw; met=0; }
    const lh=new DataView(new ArrayBuffer(30));
    lh.setUint32(0,0x04034b50,true); lh.setUint16(4,20,true); lh.setUint16(6,0x0800,true); lh.setUint16(8,met,true);
    lh.setUint16(10,hora,true); lh.setUint16(12,dia,true); lh.setUint32(14,crc,true);
    lh.setUint32(18,datos.length,true); lh.setUint32(22,raw.length,true); lh.setUint16(26,nm.length,true); lh.setUint16(28,0,true);
    partes.push(new Uint8Array(lh.buffer),nm,datos);
    const ch=new DataView(new ArrayBuffer(46));
    ch.setUint32(0,0x02014b50,true); ch.setUint16(4,20,true); ch.setUint16(6,20,true); ch.setUint16(8,0x0800,true); ch.setUint16(10,met,true);
    ch.setUint16(12,hora,true); ch.setUint16(14,dia,true); ch.setUint32(16,crc,true); ch.setUint32(20,datos.length,true); ch.setUint32(24,raw.length,true);
    ch.setUint16(28,nm.length,true); ch.setUint16(30,0,true); ch.setUint16(32,0,true); ch.setUint16(34,0,true); ch.setUint16(36,0,true);
    ch.setUint32(38,0,true); ch.setUint32(42,off,true);
    central.push(new Uint8Array(ch.buffer),nm);
    off+=30+nm.length+datos.length;
  }
  const tc=central.reduce((a,b)=>a+b.length,0), fin=new DataView(new ArrayBuffer(22));
  fin.setUint32(0,0x06054b50,true); fin.setUint16(8,lista.length,true); fin.setUint16(10,lista.length,true);
  fin.setUint32(12,tc,true); fin.setUint32(16,off,true);
  return new Blob([...partes,...central,new Uint8Array(fin.buffer)],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
}

window.ExcelFinanzas={crear,version:1};
})();
