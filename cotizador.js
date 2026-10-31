// ════════════════════════════════════════════════════════════════
//  COTIZADOR · motor de despiece (reconstruido de OCOBO) + pantallas: importar OCOBO, diseños, cotizar, histórico
//  Se carga bajo demanda desde index.html (goCot). Usa las utilidades globales de la app ($, esc, fmtN, toast, shell…).
// ════════════════════════════════════════════════════════════════
'use strict';
// ── Motor ──────────────────────────────────────────────────────────
//  Variables Cnnn = parámetro nnn del ítem (405 Ancho 1, 408 Alto 1, 501 Acabado, 505 Calibre, 502 Vidrio 1…).
//  expr: aritmética · SI[cond]op[valor][si][no] (anidable) · ?[Cx]expr (solo si Cx = concepto del renglón) · ¿[Cref][k][ancho][alto] (vidrio)
//  Resultado -1 = el renglón no va. Perfil: concepto corto × 100 + acabado (C501). Redondeo mitad arriba.
const cotRnd = x => x >= 0 ? Math.floor(x + 0.5) : -Math.floor(-x + 0.5);
const CotMotor = {
  _brackets(s, n){ const out = []; let i = 0;
    for(let k = 0; k < n; k++){ while(i < s.length && s[i] !== '[') i++; if(i >= s.length) throw new Error('Faltan corchetes: ' + s); let d = 0, j = i;
      for(;; j++){ if(j >= s.length) throw new Error('Corchete sin cerrar: ' + s); if(s[j] === '[') d++; else if(s[j] === ']'){ d--; if(!d) break; } }
      out.push(s.slice(i + 1, j)); i = j + 1; }
    return [out, s.slice(i)]; },
  ev(s, C, ctx){ s = String(s || '').trim(); if(s === '') return null;
    if(/^SI\[/i.test(s)){ const i = s.indexOf(']'); const cond = this.ev(s.slice(3, i), C, ctx); let rest = s.slice(i + 1);
      const m = rest.match(/^\s*(<>|>=|=>|<=|=<|=|<|>)\s*\[/); if(!m) throw new Error('SI sin operador: ' + s);
      const op = {'=>': '>=', '=<': '<='}[m[1]] || m[1]; rest = rest.slice(m.index + m[0].length - 1);
      const [p] = this._brackets(rest, 3); const v = this.ev(p[0], C, ctx);
      const ok = op === '=' ? cond === v : op === '<' ? cond < v : op === '>' ? cond > v : op === '>=' ? cond >= v : op === '<=' ? cond <= v : cond !== v;
      return this.ev(ok ? p[1] : p[2], C, ctx); }
    if(s.startsWith('?[')){ const i = s.indexOf(']'); ctx.cond = this.ev(s.slice(2, i), C, ctx); return this.ev(s.slice(i + 1), C, ctx); }
    let e = s.replace(/[Cc](\d{3})/g, (_, n) => { const v = C[+n]; return String(v == null ? -1 : v); }).replace(/(?<![\d.])0+(\d)/g, '$1');
    if(!/^[\d.()+\-*/ ]+$/.test(e)) throw new Error('Expresión no válida: ' + s);
    while(e){ try{ const v = Function('"use strict";return (' + e + ')')(); if(!isFinite(v)) return -1; return v; }catch(x){ e = e.slice(0, -1).trim(); } }   // OCOBO ignora lo que sobra al final
    return -1; },
  // formulas: [{orden, concepto, expr, cantidad, corte}] · refs: Map id → {descripcion, unidad, desperdicio, equivalencia, valor} · C: {405: 1507, …}
  despiece(formulas, refs, C){
    const filas = [];
    for(const f of formulas){
      const con = +f.concepto, deb = String(f.expr || '').trim(), ctx = {cond: null}; let ref, dx = 0, dy = 0, area = false;
      try{
        if(deb.startsWith('¿[') || deb.startsWith('[')){
          const [p] = this._brackets(deb.slice(deb.indexOf('[')), deb[0] === '[' ? 3 : 4); let k;
          if(deb[0] === '['){ ref = con; [, dx, dy] = [p[0], this.ev(p[1], C, ctx), this.ev(p[2], C, ctx)]; k = p[0]; } else { ref = this.ev(p[0], C, ctx); dx = this.ev(p[2], C, ctx); dy = this.ev(p[3], C, ctx); k = p[1]; }
          if(!(ref > 0) || dx == null || dx < 0 || dy == null || dy < 0) continue;
          dx = cotRnd(dx); dy = cotRnd(dy); area = true; ref = Math.round(ref);
        } else {
          let v = this.ev(deb, C, ctx);
          if(deb && ctx.cond != null && Math.round(ctx.cond) !== con) continue;
          if(v == null) v = 0; if(v < 0) continue;
          dx = cotRnd(v); ref = con < 10000 ? con * 100 + Math.round(C[501] || 0) : con;
        }
        const cant = f.cantidad ? this.ev(f.cantidad, C, ctx) : 1; if(!(cant > 0)) continue;
        const r = refs.get(ref);
        if(!r){ filas.push({orden: f.orden, ref, concepto: con, dx, dy, cant, medx: null, medy: null, valor: null, corte: +f.corte || 0, err: 'Referencia ' + ref + ' no existe'}); continue; }
        const eq = +r.equivalencia || 1; let medx, medy, valor;
        if(area || ((r.unidad === 22922 || r.unidad === 22923) && dy > 0)){ medx = dx; medy = dy; valor = cotRnd(dx * dy * cant / eq * +r.valor); }
        else if(dx > 0 && r.unidad === 22921){ medx = (dx + (+r.desperdicio || 0)) * cant; medy = 1; valor = cotRnd(medx / eq * +r.valor); }
        else { medx = cant; medy = 1; valor = cotRnd(cant / eq * +r.valor); }
        filas.push({orden: f.orden, ref, concepto: con, descripcion: r.descripcion, categoria: r.categoria, dx, dy, cant, medx, medy, unitario: +r.valor, valor, corte: +f.corte || 0, lineal: dx > 0 && r.unidad === 22921, area: area || ((r.unidad === 22922 || r.unidad === 22923) && dy > 0)});
      }catch(e){ filas.push({orden: f.orden, ref: ref || con, concepto: con, dx: 0, dy: 0, cant: 0, valor: null, err: e.message}); }
    }
    return filas;
  },
  // Totales comerciales por unidad: com = {301 costos %, 302 instalación $/m², 303 % de participación (materiales+instalación = este % del precio), 304 IVA MP %, 310 descuento $, 312/313/314 A·I·U %, 316 IVA sobre utilidad %, 317 valor M.O $, 319 instalación ML $}
  totales(mp, m2, com){
    const g = k => +com[k] || 0;
    const costos = cotRnd(mp * g(301) / 100), inst = cotRnd(g(302) * m2), vmo = g(317), instMl = g(319), vt = g(308);
    const base = mp + costos + inst + vmo + instMl + vt;
    const adic = g(303) ? cotRnd(base * (100 - g(303)) / g(303)) : 0, ivamp = cotRnd(mp * g(304) / 100);
    const sub1 = base + adic + ivamp, desc = g(310), neto = sub1 - desc;
    const A = g(312), I = g(313), U = g(314);
    const mat = cotRnd(neto / (1 + (A + I + U) / 100)), a = cotRnd(mat * A / 100), i = cotRnd(mat * I / 100), u = cotRnd(mat * U / 100), ivau = cotRnd(u * g(316) / 100);
    return {mp, costos, inst, vmo, instMl, adic, ivamp, sub1, desc, mat, A: a, I: i, U: u, ivau, total: neto + ivau};
  }
};
window.CotMotor = CotMotor;

// ── Estado y datos ─────────────────────────────────────────────────
const CT = {tab: 'cotizar', cargado: false, dis: [], refs: new Map(), opc: new Map(), conc: new Map(), form: new Map(), q: '', sel: null, doc: {obra: '', cliente: '', items: [], com: {301: 0, 302: 35000, 303: 83, 304: 19, 312: 10, 313: 4, 314: 6, 316: 19}}, hist: null, imp: null};
window.CT = CT;
const ctCOP = v => v == null ? '—' : '$ ' + fmtN(Math.round(v));
async function ctCargar(){
  if(CT.cargado) return;
  const [d, r, o, c] = await Promise.all([
    API.all(x => API.sb.from('cot_diseno').select('id,nombre,sistema,tipologia,params,usado,ultimo_uso,activo', x).order('id')),
    API.all(x => API.sb.from('cot_referencia').select('id,descripcion,unidad,desperdicio,equivalencia,valor,categoria,categoria_nombre,activo', x).order('id')),
    API.all(x => API.sb.from('cot_opcion').select('*', x).order('concepto').order('valor')),
    API.sb.from('cot_concepto').select('*').then(x => { if(x.error) throw x.error; return x.data || []; })]);
  CT.dis = d; CT.refs = new Map(r.map(x => [+x.id, x])); CT.conc = new Map(c.map(x => [+x.id, x.nombre]));
  CT.opc = new Map(); for(const x of o){ if(!CT.opc.has(+x.concepto)) CT.opc.set(+x.concepto, []); CT.opc.get(+x.concepto).push(x); }
  CT.cargado = true;
}
async function ctFormulas(diseno){
  if(CT.form.has(diseno)) return CT.form.get(diseno);
  const {data, error} = await API.sb.from('cot_formula').select('orden,concepto,expr,cantidad,corte').eq('diseno', diseno).order('orden'); if(error) throw error;
  CT.form.set(diseno, data || []); return data || [];
}
window.goCot = async function(){
  if(!(isGerente() || rolEs('cotizaciones'))) return;
  if(S.view !== 'cot') history.pushState({v: 'cot'}, ''); S.view = 'cot'; aplicarEmpresa(); window.scrollTo(0, 0);
  $('#app').innerHTML = shell('<div class="loading"><div class="spin"></div>Cargando el cotizador</div>');
  try{ await ctCargar(); }catch(e){ CT.err = /cot_|PGRST205|42P01/.test(errMsg(e) + (e.code || '')) ? 'Falta activar el cotizador en la base (SQL 115)' : errMsg(e); }
  renderCot();
};
window.renderCot = function(){
  const tabs = [['cotizar', 'Cotizar'], ['dis', 'Diseños'], ['hist', 'Histórico OCOBO'], ['imp', 'Importar OCOBO']];
  let body;
  if(CT.err) body = `<div class="warn">${esc(CT.err)}</div>` + (CT.tab === 'imp' ? ctImpHTML() : '');
  else if(!CT.dis.length && CT.tab !== 'imp') body = `<div class="warn">Todavía no hay diseños. Importe primero los archivos de OCOBO.</div>` + ctImpHTML();
  else body = CT.tab === 'imp' ? ctImpHTML() : CT.tab === 'dis' ? ctDisHTML() : CT.tab === 'hist' ? ctHistHTML() : ctCotizarHTML();
  $('#app').innerHTML = shell(`<div class="tabs">${tabs.map(([k, n]) => `<button class="tab ${CT.tab === k ? 'on' : ''}" onclick="CT.tab='${k}';renderCot()">${n}</button>`).join('')}</div>
    <div class="art-head"><div><div class="h1">Cotizador</div><div class="h1-sub">${fmtN(CT.dis.length)} diseños · ${fmtN(CT.refs.size)} referencias con precio · motor de despiece propio (validado contra OCOBO)</div></div></div>${body}`);
  if(CT.tab === 'hist' && !CT.hist) ctHistCargar();
};

// ── Importar OCOBO ─────────────────────────────────────────────────
function ctImpHTML(){
  return `<div class="cot-box"><div class="cot-h">Importar la base de OCOBO</div>
    <div class="cot-d">Elija los archivos JSON exportados del volcado de OCOBO (ocobo_conceptos, ocobo_referencias, ocobo_disenos, ocobo_formulas, ocobo_opciones, ocobo_documentos, ocobo_items, ocobo_despiece). Puede elegirlos todos a la vez; se cargan en orden. Se puede repetir: actualiza lo que ya existe.</div>
    <label class="btn primary">Elegir archivos JSON<input type="file" accept=".json" multiple style="display:none" onchange="ctImportar(this.files)"></label>
    <div id="ctImpLog" class="sc-note" style="margin-top:10px;white-space:pre-line">${esc(CT.imp || '')}</div></div>`;
}
window.ctImportar = async function(files){
  const orden = ['conceptos', 'referencias', 'disenos', 'formulas', 'opciones', 'documentos', 'items', 'despiece'];
  const tabla = {conceptos: 'cot_concepto', referencias: 'cot_referencia', disenos: 'cot_diseno', formulas: 'cot_formula', opciones: 'cot_opcion', documentos: 'cot_documento', items: 'cot_item', despiece: 'cot_despiece'};
  const clave = {conceptos: 'id', referencias: 'id', disenos: 'id', formulas: 'diseno,orden', opciones: 'concepto,valor', documentos: 'interno', items: 'interno,item', despiece: 'interno,item'};
  const lista = [...files].map(f => ({f, k: orden.find(k => f.name.includes(k))})).filter(x => x.k).sort((a, b) => orden.indexOf(a.k) - orden.indexOf(b.k));
  if(!lista.length) return toast('Ningún archivo reconocido (deben llamarse ocobo_*.json)', true);
  const log = m => { CT.imp = (CT.imp || '') + m + '\n'; const e = $('#ctImpLog'); if(e){ e.textContent = CT.imp; } };
  CT.imp = '';
  for(const {f, k} of lista){
    log(`${f.name}: leyendo…`);
    let data; try{ data = JSON.parse(await f.text()); }catch(e){ log('  ✕ no es un JSON válido'); continue; }
    let filas = data;
    if(k === 'formulas') filas = data.map(r => ({diseno: r[0], orden: r[1], concepto: r[2], expr: r[3], cantidad: r[4] || '1', corte: r[5] || ''}));
    if(k === 'opciones') filas = data.map(r => ({concepto: r[0], valor: r[1], etiqueta: r[2], usos: r[3] || 0}));
    if(k === 'referencias') filas = data.map(r => ({...r, unitario: r.unitario || (r.valor && r.equivalencia ? r.valor / r.equivalencia : 0)}));
    // sin duplicados por clave (el upsert falla si el mismo lote trae dos veces la misma clave)
    const ks = clave[k].split(','); const vistos = new Set(); filas = filas.filter(r => { const id = ks.map(c => r[c]).join('|'); if(vistos.has(id)) return false; vistos.add(id); return true; });
    const N = k === 'despiece' ? 200 : k === 'items' ? 500 : 2000; let ok = 0;
    for(let i = 0; i < filas.length; i += N){
      const lote = filas.slice(i, i + N);
      const {error} = await API.sb.from(tabla[k]).upsert(lote, {onConflict: clave[k]});
      if(error){ log(`  ✕ error en el lote ${i / N + 1}: ${errMsg(error)}`); break; }
      ok += lote.length; if((i / N) % 10 === 0 || ok === filas.length) log(`  ${fmtN(ok)} de ${fmtN(filas.length)}`);
    }
    log(`  ✓ ${f.name}: ${fmtN(ok)} filas`);
  }
  log('Listo.'); CT.cargado = false; CT.form.clear(); CT.hist = null; toast('✓ Importación terminada'); try{ await ctCargar(); }catch(e){} renderCot();
};

// ── Diseños ────────────────────────────────────────────────────────
const ctNorm = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase();
function ctBuscar(q){ const t = ctNorm(q).split(/\s+/).filter(Boolean); return CT.dis.filter(d => d.activo !== false && t.every(w => ctNorm(d.nombre + ' ' + (d.sistema || '') + ' ' + (d.tipologia || '') + ' ' + d.id).includes(w))); }
function ctDisHTML(){
  const l = ctBuscar(CT.q).sort((a, b) => (b.ultimo_uso || '').localeCompare(a.ultimo_uso || '') || b.usado - a.usado).slice(0, 200);
  return `<div class="filters" style="grid-template-columns:1fr"><div class="search">${ICON.search}<input id="ctQ" placeholder="Buscar diseño: sistema, perfiles, tipología (XO, OXO, X>)…" value="${esc(CT.q)}"></div></div>
    <div class="sc-note" style="margin-bottom:8px">${fmtN(l.length)} diseños${l.length === 200 ? ' (los 200 más recientes)' : ''} · ordenados por último uso</div>
    <table class="cp-tbl"><thead><tr><th style="text-align:left">Diseño</th><th style="text-align:left">Sistema</th><th style="text-align:left">Tipología</th><th>Veces</th><th>Último uso</th><th></th></tr></thead><tbody>
    ${l.map(d => `<tr><td><b>${esc(d.nombre)}</b><br><small>${d.id}</small></td><td>${esc(d.sistema || '')}</td><td>${esc(d.tipologia || '')}</td><td style="text-align:center">${fmtN(d.usado)}</td><td style="text-align:center">${d.ultimo_uso ? fmtD(d.ultimo_uso) : '—'}</td>
      <td style="white-space:nowrap"><button class="btn sm" onclick="ctVerDiseno(${d.id})">Fórmula</button><button class="btn sm primary" onclick="ctAgregarItem(${d.id})">Cotizar</button></td></tr>`).join('')}</tbody></table>`;
}
window.ctVerDiseno = async function(id){
  const d = CT.dis.find(x => x.id === id); if(!d) return;
  let f; try{ f = await ctFormulas(id); }catch(e){ return toast(errMsg(e), true); }
  const nom = c => { const r = CT.refs.get(c < 10000 ? c * 100 + 3 : c); return r ? r.descripcion.replace(/ Pin\. Negra H3$/, '') : c === 6 ? 'Vidrio' : String(c); };
  openSheet('Fórmula del diseño', d.nombre, `<div class="sc-note">${f.length} renglones. Parámetros que pide: ${d.params.map(p => esc(CT.conc.get(16000 + p.c) || 'C' + p.c)).join(', ') || '—'}</div>
    <table class="cp-tbl" style="font-size:12px"><thead><tr><th>#</th><th style="text-align:left">Referencia</th><th style="text-align:left">Medida</th><th>Cant.</th><th>Corte</th></tr></thead><tbody>
    ${f.map(x => `<tr><td>${x.orden}</td><td>${esc(nom(+x.concepto))}</td><td class="mono" style="font-family:var(--mono)">${esc(x.expr)}</td><td style="text-align:center">${esc(x.cantidad)}</td><td style="text-align:center">${esc(x.corte)}</td></tr>`).join('')}</tbody></table>`, null);
};

// ── Cotizar ────────────────────────────────────────────────────────
const CT_P = {405: 'Ancho 1', 406: 'Ancho 2', 407: 'Ancho 3', 408: 'Alto 1', 409: 'Alto 2', 410: 'Alto 3', 411: 'Ancho V1', 412: 'Ancho V2', 413: 'Ancho V3', 414: 'Alto V1', 415: 'Alto V2', 416: 'Alto V3', 404: 'Cantidad PER', 401: 'Cantidad PER 2', 403: 'm²'};
const ctSelParam = c => c >= 501;   // los 5xx son de selección (acabado, vidrio, calibre…)
window.ctAgregarItem = async function(id){
  const d = CT.dis.find(x => x.id === id); if(!d) return;
  const C = {}; for(const p of d.params) if(p.c >= 401 && p.c <= 599) C[p.c] = p.def || 0;
  // valores por defecto útiles
  if(C[501] === 0 && d.params.some(p => p.c === 501)) C[501] = 3;
  const it = {diseno: id, nombre: d.nombre, descripcion: '', nomenclatura: 'V-' + (CT.doc.items.length + 1), cantidad: 1, C, com: {...CT.doc.com}, filas: null, tot: null};
  CT.doc.items.push(it); CT.sel = CT.doc.items.length - 1; CT.tab = 'cotizar'; await ctRecalcular(it); renderCot();
};
async function ctRecalcular(it){
  const f = await ctFormulas(it.diseno);
  // m² automático si el diseño no lo trae: ancho 1 × alto 1
  if(!(it.C[403] > 0) && it.C[405] > 0 && it.C[408] > 0) it.C[403] = Math.round(it.C[405] * it.C[408] / 1e6 * 100) / 100;
  it.filas = CotMotor.despiece(f, CT.refs, it.C);
  const mp = it.filas.reduce((a, x) => a + (x.valor || 0), 0);
  it.tot = CotMotor.totales(mp, +it.C[403] || 0, it.com);
}
window.ctSet = async function(k, c, v){ const it = CT.doc.items[k]; if(!it) return; it.C[c] = v === '' ? -1 : +v; if(c === 405 || c === 408) it.C[403] = 0; await ctRecalcular(it); renderCot(); };
window.ctSetCom = async function(k, c, v){ const it = CT.doc.items[k]; if(!it) return; it.com[c] = +v || 0; await ctRecalcular(it); renderCot(); };
window.ctSetItem = function(k, campo, v){ const it = CT.doc.items[k]; if(it) it[campo] = campo === 'cantidad' ? Math.max(1, +v || 1) : v; };
window.ctQuitar = function(k){ CT.doc.items.splice(k, 1); CT.sel = Math.min(CT.sel, CT.doc.items.length - 1); renderCot(); };
window.ctDuplicar = async function(k){ const o = CT.doc.items[k]; const it = JSON.parse(JSON.stringify(o)); it.nomenclatura = 'V-' + (CT.doc.items.length + 1); CT.doc.items.splice(k + 1, 0, it); CT.sel = k + 1; await ctRecalcular(it); renderCot(); };
window.ctAplicarTodos = async function(c, v){ for(const it of CT.doc.items){ if(c in it.C || c >= 501){ it.C[c] = +v; await ctRecalcular(it); } } renderCot(); toast('✓ Aplicado a todos los ítems'); };
function ctParamInput(k, it, c){
  const d = CT.dis.find(x => x.id === it.diseno), nom = CT.conc.get(16000 + c) || CT_P[c] || 'C' + c, v = it.C[c];
  if(ctSelParam(c)){
    let ops = CT.opc.get(c) || [];
    // vidrio / felpa / alfajía / brazo: la lista son referencias, se arma de las opciones usadas + búsqueda por descripción
    const actual = ops.find(o => +o.valor === +v);
    return `<div class="field" style="margin:0"><span class="lbl">${esc(nom)}</span><select onchange="ctSet(${k}, ${c}, this.value)"><option value="0" ${!(v > 0) ? 'selected' : ''}>—</option>${ops.filter(o => +o.valor > 0).map(o => `<option value="${o.valor}" ${+o.valor === +v ? 'selected' : ''}>${esc(o.etiqueta)}</option>`).join('')}${v > 0 && !actual ? `<option value="${v}" selected>${esc((CT.refs.get(+v) || {}).descripcion || v)}</option>` : ''}</select></div>`;
  }
  return `<div class="field" style="margin:0"><span class="lbl">${esc(nom)}${c >= 404 && c <= 416 && c !== 403 ? ' (mm)' : ''}</span><input type="number" step="${c === 403 ? '0.01' : '1'}" value="${v > 0 ? v : ''}" onchange="ctSet(${k}, ${c}, this.value)" style="max-width:120px"></div>`;
}
function ctCotizarHTML(){
  const D = CT.doc, k = CT.sel, it = D.items[k];
  const totDoc = D.items.reduce((a, x) => a + (x.tot ? x.tot.total * x.cantidad : 0), 0), m2Doc = D.items.reduce((a, x) => a + (+x.C[403] || 0) * x.cantidad, 0);
  let h = `<div class="cot-box"><div class="cot-h">Cotización nueva</div>
    <div class="fgrid"><div class="field"><span class="lbl">Obra / proyecto</span><input value="${esc(D.obra)}" onchange="CT.doc.obra=this.value"></div><div class="field"><span class="lbl">Cliente</span><input value="${esc(D.cliente)}" onchange="CT.doc.cliente=this.value"></div></div>
    <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end;margin-top:6px"><div class="search" style="flex:1;min-width:240px">${ICON.search}<input id="ctQ2" placeholder="Buscar diseño para agregar (ej. ELIPSE XO, FERRARA, ABSOLUTE 041)…" value="${esc(CT.q2 || '')}"></div></div>
    ${CT.q2 ? `<div style="max-height:220px;overflow:auto;margin-top:6px">${ctBuscar(CT.q2).sort((a, b) => b.usado - a.usado).slice(0, 30).map(d => `<div class="as-row" style="padding:5px 0"><div class="as-n"><b>${esc(d.nombre)}</b><span class="cot-d" style="margin:0">${fmtN(d.usado)} usos${d.ultimo_uso ? ' · último ' + fmtD(d.ultimo_uso) : ''}</span></div><button class="btn sm primary" onclick="CT.q2='';ctAgregarItem(${d.id})">Agregar</button></div>`).join('') || '<div class="cot-d">Sin resultados</div>'}</div>` : ''}</div>`;
  if(!D.items.length) return h + '<div class="empty">Busque un diseño y agréguelo para empezar a cotizar.</div>';
  h += `<div class="cot-box"><div class="cot-h">Ítems (${D.items.length}) · ${fmtN(m2Doc, 2)} m² · total <b>${ctCOP(totDoc)}</b></div>
    <table class="cp-tbl"><thead><tr><th>#</th><th style="text-align:left">Diseño</th><th style="text-align:left">Ubicación</th><th>Ancho</th><th>Alto</th><th>m²</th><th>Cant.</th><th>Unitario</th><th>Total</th><th></th></tr></thead><tbody>
    ${D.items.map((x, i) => `<tr style="cursor:pointer;${i === k ? 'background:var(--surface2)' : ''}" onclick="CT.sel=${i};renderCot()"><td>${esc(x.nomenclatura)}</td><td><b>${esc(x.nombre)}</b>${x.filas && x.filas.some(f => f.err) ? ' <b style="color:var(--danger)">⚠</b>' : ''}</td><td>${esc(x.descripcion)}</td><td style="text-align:center">${fmtN(x.C[405])}</td><td style="text-align:center">${fmtN(x.C[408])}</td><td style="text-align:center">${fmtN(x.C[403], 2)}</td><td style="text-align:center">${x.cantidad}</td><td style="text-align:right">${x.tot ? ctCOP(x.tot.total) : '—'}</td><td style="text-align:right"><b>${x.tot ? ctCOP(x.tot.total * x.cantidad) : '—'}</b></td>
      <td style="white-space:nowrap"><button class="btn sm ghost" onclick="event.stopPropagation();ctDuplicar(${i})">⧉</button><button class="btn sm ghost" onclick="event.stopPropagation();ctQuitar(${i})">✕</button></td></tr>`).join('')}</tbody></table></div>`;
  if(!it) return h;
  const d = CT.dis.find(x => x.id === it.diseno) || {params: []};
  const ps = d.params.map(p => p.c).filter(c => c >= 401 && c <= 599 && c !== 403 && c !== 419 && c !== 420);
  const grupos = {Aluminio: [], Vidrio: [], 'Accesorios de ensamble': [], 'Accesorios de instalación': [], Otros: []};
  for(const f of it.filas || []){ const g = f.categoria === 16050 ? 'Aluminio' : f.categoria === 16054 ? 'Vidrio' : f.concepto >= 300000 && f.concepto < 400000 ? (f.categoria === 16051 || f.categoria === 16055 ? 'Accesorios de ensamble' : 'Accesorios de instalación') : 'Otros'; grupos[g].push(f); }
  const T = it.tot || {};
  h += `<div class="cot-box"><div class="cot-h">${esc(it.nomenclatura)} · ${esc(it.nombre)} <button class="btn sm ghost" onclick="ctVerDiseno(${it.diseno})">Ver fórmula</button></div>
    <div class="fgrid"><div class="field"><span class="lbl">Ubicación / descripción</span><input value="${esc(it.descripcion)}" onchange="ctSetItem(${k}, 'descripcion', this.value)"></div><div class="field"><span class="lbl">Nomenclatura</span><input value="${esc(it.nomenclatura)}" onchange="ctSetItem(${k}, 'nomenclatura', this.value);renderCot()" style="max-width:120px"></div><div class="field"><span class="lbl">Cantidad</span><input type="number" min="1" value="${it.cantidad}" onchange="ctSetItem(${k}, 'cantidad', this.value);renderCot()" style="max-width:100px"></div></div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:8px 14px;margin-top:8px">${ps.map(c => ctParamInput(k, it, c)).join('')}</div>
    <div class="cot-d" style="margin-top:8px">m² del ítem: <b>${fmtN(it.C[403], 2)}</b> · <button class="btn sm ghost" onclick="ctAplicarTodos(501, ${it.C[501] || 0})">Aplicar este acabado a todos</button> ${it.C[502] > 0 ? `<button class="btn sm ghost" onclick="ctAplicarTodos(502, ${it.C[502]})">Aplicar este vidrio a todos</button>` : ''}</div></div>
    <div class="cot-box"><div class="cot-h">Despiece por unidad · materia prima ${ctCOP(T.mp)}</div>
    ${Object.entries(grupos).filter(([, l]) => l.length).map(([g, l]) => `<div style="font-weight:700;font-size:13px;margin:8px 0 2px;letter-spacing:.06em">${g} · ${ctCOP(l.reduce((a, f) => a + (f.valor || 0), 0))}</div>
      <table class="cp-tbl" style="font-size:12.5px"><tbody>${l.map(f => `<tr${f.err ? ' style="color:var(--danger)"' : ''}><td style="width:60%">${esc(f.descripcion || f.ref)}${f.err ? ' · ' + esc(f.err) : ''}</td><td style="text-align:right">${f.area ? fmtN(f.dx) + ' × ' + fmtN(f.dy) + ' mm' : f.lineal ? fmtN(f.dx) + ' mm' : ''}</td><td style="text-align:center">× ${fmtN(f.cant)}</td><td style="text-align:right">${ctCOP(f.valor)}</td></tr>`).join('')}</tbody></table>`).join('')}</div>
    <div class="cot-box"><div class="cot-h">Precio por unidad</div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px 14px">${[[301, 'Costos %'], [302, 'Instalación $/m²'], [303, 'Participación MP+inst. %'], [304, 'IVA materia prima %'], [317, 'Valor M.O. $'], [312, 'Administración %'], [313, 'Imprevistos %'], [314, 'Utilidad %'], [316, 'IVA sobre utilidad %'], [310, 'Descuento $']].map(([c, n]) => `<div class="field" style="margin:0"><span class="lbl">${n}</span><input type="number" step="any" value="${it.com[c] ?? ''}" onchange="ctSetCom(${k}, ${c}, this.value)"></div>`).join('')}</div>
    <table class="cp-tbl" style="margin-top:10px;max-width:520px"><tbody>
      <tr><td>Materia prima</td><td style="text-align:right">${ctCOP(T.mp)}</td></tr><tr><td>Costos (${it.com[301] || 0} %)</td><td style="text-align:right">${ctCOP(T.costos)}</td></tr><tr><td>Instalación (${fmtN(it.com[302])} $/m² × ${fmtN(it.C[403], 2)})</td><td style="text-align:right">${ctCOP(T.inst)}</td></tr>
      ${T.vmo ? `<tr><td>Valor M.O.</td><td style="text-align:right">${ctCOP(T.vmo)}</td></tr>` : ''}<tr><td>Adicional (MP + inst. = ${it.com[303] || 0} % del precio)</td><td style="text-align:right">${ctCOP(T.adic)}</td></tr><tr><td>IVA materia prima</td><td style="text-align:right">${ctCOP(T.ivamp)}</td></tr>
      <tr><td><b>Subtotal</b></td><td style="text-align:right"><b>${ctCOP(T.sub1)}</b></td></tr>${T.desc ? `<tr><td>Descuento</td><td style="text-align:right">− ${ctCOP(T.desc)}</td></tr>` : ''}
      <tr><td style="color:var(--muted)">Materiales ${ctCOP(T.mat)} · A ${ctCOP(T.A)} · I ${ctCOP(T.I)} · U ${ctCOP(T.U)}</td><td style="text-align:right;color:var(--muted)">IVA util. ${ctCOP(T.ivau)}</td></tr>
      <tr><td><b>TOTAL por unidad</b></td><td style="text-align:right"><b style="font-size:16px">${ctCOP(T.total)}</b></td></tr><tr><td>× ${it.cantidad} unidades</td><td style="text-align:right"><b>${ctCOP((T.total || 0) * it.cantidad)}</b></td></tr></tbody></table>
    <div class="cot-d" style="margin-top:8px">Precios de referencia: los de OCOBO al momento de la exportación. Pendiente: enlazarlos con el catálogo de compras.</div></div>`;
  return h;
}

// ── Histórico OCOBO ────────────────────────────────────────────────
async function ctHistCargar(){
  try{ const {data, error} = await API.sb.from('cot_documento').select('interno,tipo,numero,fecha,obra,usuario,procedencia').order('fecha', {ascending: false}).limit(400); if(error) throw error; CT.hist = data || []; }
  catch(e){ CT.hist = []; toast(errMsg(e), true); }
  renderCot();
}
function ctHistHTML(){
  if(!CT.hist) return '<div class="loading"><div class="spin"></div>Cargando el histórico</div>';
  const q = ctNorm(CT.qh || ''), l = CT.hist.filter(d => !q || ctNorm(d.obra + ' ' + d.numero + ' ' + d.tipo).includes(q));
  return `<div class="filters" style="grid-template-columns:1fr"><div class="search">${ICON.search}<input id="ctQh" placeholder="Buscar obra o número…" value="${esc(CT.qh || '')}"></div></div>
    <div class="sc-note" style="margin-bottom:8px">Últimos 400 documentos de OCOBO (solo lectura). Al abrir uno se recalcula con el motor propio y se compara con lo que guardó OCOBO.</div>
    <div class="art-ops">${l.map(d => `<div class="art-op"><button class="art-lote" style="width:100%;text-align:left;cursor:pointer" onclick="ctHistAbrir(${d.interno})"><div><b>${d.tipo === 'op' ? 'OP' : 'Cotización'} ${d.numero}</b><span>${d.fecha ? fmtD(d.fecha) : ''} · ${esc(d.obra || '')}${d.usuario ? ' · ' + esc(d.usuario) : ''}</span></div></button></div>`).join('')}</div>`;
}
window.ctHistAbrir = async function(interno){
  toast('Abriendo…');
  try{
    const [{data: items, error: e1}, {data: doc}] = await Promise.all([API.sb.from('cot_item').select('*').eq('interno', interno).order('item'), API.sb.from('cot_documento').select('*').eq('interno', interno).single()]);
    if(e1) throw e1;
    let tot = 0, filasOc = 0, ok = 0;
    const filas = [];
    for(const it of items){
      let mio = null; try{ const f = await ctFormulas(it.diseno); const C = {}; for(const [k, v] of Object.entries(it.params)) C[+k] = +v; mio = CotMotor.despiece(f, CT.refs, C); }catch(e){}
      const mp = mio ? mio.reduce((a, x) => a + (x.valor || 0), 0) : 0;
      const T = CotMotor.totales(mp, +it.params['403'] || 0, Object.fromEntries(Object.entries(it.comercial).map(([k, v]) => [+k, v])));
      tot += T.total * it.cantidad;
      filas.push(`<tr><td>${esc(it.nomenclatura)}</td><td>${esc((CT.dis.find(d => d.id === it.diseno) || {}).nombre || it.diseno)}<br><small>${esc(it.descripcion)}</small></td><td style="text-align:center">${fmtN(it.params['405'])} × ${fmtN(it.params['408'])}</td><td style="text-align:center">${it.cantidad}</td><td style="text-align:right">${mio ? fmtN(mio.length) : '—'}</td><td style="text-align:right">${ctCOP(T.total)}</td></tr>`);
    }
    openSheet(`${doc.tipo === 'op' ? 'OP' : 'Cotización'} ${doc.numero} · ${esc(doc.obra || '')}`, `${doc.fecha ? fmtD(doc.fecha) : ''} · ${items.length} ítems · recalculado hoy: ${ctCOP(tot)}`,
      `<table class="cp-tbl"><thead><tr><th>Nom.</th><th style="text-align:left">Diseño</th><th>Medidas</th><th>Cant.</th><th>Renglones</th><th>Unitario (hoy)</th></tr></thead><tbody>${filas.join('')}</tbody></table>
       <div class="cot-d" style="margin-top:8px">Precio unitario recalculado con el motor propio y los precios actuales de referencia. ${doc.tipo === 'cotizacion' ? '<button class="btn sm" onclick="ctCopiarDoc(' + interno + ')">Usar como base de una cotización nueva</button>' : ''}</div>`, null);
  }catch(e){ toast(errMsg(e), true); }
};
window.ctCopiarDoc = async function(interno){
  const {data: items, error} = await API.sb.from('cot_item').select('*').eq('interno', interno).order('item'); if(error) return toast(errMsg(error), true);
  const {data: doc} = await API.sb.from('cot_documento').select('*').eq('interno', interno).single();
  CT.doc = {obra: (doc && doc.obra) || '', cliente: '', items: [], com: {...CT.doc.com}};
  for(const it of items){ const d = CT.dis.find(x => x.id === it.diseno); if(!d) continue; const C = {}; for(const [k, v] of Object.entries(it.params)) C[+k] = +v; const com = {}; for(const [k, v] of Object.entries(it.comercial)) com[+k] = v;
    const x = {diseno: it.diseno, nombre: d.nombre, descripcion: it.descripcion, nomenclatura: it.nomenclatura, cantidad: it.cantidad, C, com, filas: null, tot: null}; await ctRecalcular(x); CT.doc.items.push(x); }
  CT.sel = 0; CT.tab = 'cotizar'; closeSheet(); renderCot(); toast('✓ Cotización copiada: ' + CT.doc.items.length + ' ítems');
};
// buscadores con foco estable
document.addEventListener('input', e => {
  if(e.target.id === 'ctQ'){ CT.q = e.target.value; const p = e.target.selectionStart; renderCot(); const j = $('#ctQ'); if(j){ j.focus(); j.setSelectionRange(p, p); } }
  if(e.target.id === 'ctQ2'){ CT.q2 = e.target.value; const p = e.target.selectionStart; renderCot(); const j = $('#ctQ2'); if(j){ j.focus(); j.setSelectionRange(p, p); } }
  if(e.target.id === 'ctQh'){ CT.qh = e.target.value; const p = e.target.selectionStart; renderCot(); const j = $('#ctQh'); if(j){ j.focus(); j.setSelectionRange(p, p); } }
});
