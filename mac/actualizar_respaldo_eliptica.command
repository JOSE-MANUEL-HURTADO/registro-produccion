#!/bin/zsh
# ════════════════════════════════════════════════════════════════
#  ELÍPTICA · Actualizar la copia de seguridad automática (Mac)
#  Uso: abre Terminal y escribe   zsh ~/Downloads/actualizar_respaldo_eliptica.command
#  No pregunta nada: conserva usuario, contraseña, carpeta y hora.
#  Desde ahora la copia diaria guarda también todas las tablas (.zip) y los PDF de OP.
# ════════════════════════════════════════════════════════════════
set -e
DIR="$HOME/Library/Application Support/EliptikaRespaldo"
LOG="$HOME/Library/Logs/EliptikaRespaldo.log"
LABEL="co.eliptica.respaldo"
[[ -f "$DIR/config.json" ]] || { echo "✗ No encuentro la copia automática instalada en este Mac. Usa instalar_respaldo_eliptica.command"; exit 1; }
cp "$DIR/respaldo.js" "$DIR/respaldo.anterior.js" 2>/dev/null || true
cat > "$DIR/respaldo.js" <<'EOF_JS'
// ════════════════════════════════════════════════════════════════
//  ELÍPTICA · Copia de seguridad automática de la base de producción
//  Se ejecuta en el Mac con:  osascript -l JavaScript respaldo.js
//  Descarga la base completa (vista base_exportable) y la guarda como
//  COPIA_SEGURIDAD_AAAA-MM-DD_HHMM.xlsx, con el mismo formato que la BASE_,
//  así que se puede usar en "Reemplazar base completa" si algún día hace falta.
// ════════════════════════════════════════════════════════════════

// ── Generador de Excel (.xlsx) ──────────────────────────────────
function xmlEsc(v){
  return String(v).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function colName(i){ let s = ''; i++; while(i > 0){ const m = (i-1) % 26; s = String.fromCharCode(65+m) + s; i = Math.floor((i-1)/26); } return s; }
function serial(s){ const p = String(s).slice(0,10).split('-').map(Number); return (Date.UTC(p[0], p[1]-1, p[2]) - Date.UTC(1899,11,30)) / 864e5; }

function buildParts(rows){
  const cols = Object.keys(rows[0]);
  const isDate = cols.map(c => /^(FECHA|DIA )/.test(c));
  const L = cols.map((c,i) => colName(i));
  const out = [];
  out.push('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' +
    '<cols>' + cols.map((c,i) => `<col min="${i+1}" max="${i+1}" width="${Math.max(10, Math.min(28, c.length+2))}" customWidth="1"/>`).join('') + '</cols><sheetData>');
  out.push('<row r="1">' + cols.map((c,i) => `<c r="${L[i]}1" t="inlineStr"><is><t>${xmlEsc(c)}</t></is></c>`).join('') + '</row>');
  for(let r = 0; r < rows.length; r++){
    const row = rows[r], n = r + 2;
    let x = `<row r="${n}">`;
    for(let i = 0; i < cols.length; i++){
      const v = row[cols[i]];
      if(v === null || v === undefined || v === '') continue;
      const ref = L[i] + n;
      if(isDate[i] && /^\d{4}-\d{2}-\d{2}/.test(v)) x += `<c r="${ref}" s="1"><v>${serial(v)}</v></c>`;
      else if(typeof v === 'number' && isFinite(v)) x += `<c r="${ref}"><v>${v}</v></c>`;
      else if(typeof v === 'boolean') x += `<c r="${ref}" t="inlineStr"><is><t>${v ? 'SI' : 'NO'}</t></is></c>`;
      else x += `<c r="${ref}" t="inlineStr"><is><t xml:space="preserve">${xmlEsc(v)}</t></is></c>`;
    }
    out.push(x + '</row>');
  }
  out.push(`</sheetData><autoFilter ref="A1:${L[cols.length-1]}${rows.length+1}"/></worksheet>`);
  return {
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Hoja1" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">Hoja1!$A$1:$' + L[cols.length-1] + '$' + (rows.length+1) + '</definedName></definedNames></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/></numFmts><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
    'xl/worksheets/sheet1.xml': out.join('\n')
  };
}

// ── Ejecución en el Mac (JavaScript for Automation) ─────────────
// Si falla (internet caído, Mac recién despertado, Supabase lento) lo reintenta 2 veces más, cada 5 minutos
function run(argv){
  let ult;
  for(let k = 1; k <= 3; k++){
    try{ return respaldar(k, 3); }catch(e){ ult = e; if(k < 3) delay(300); }
  }
  throw ult;
}
function respaldar(intento, total){
  ObjC.import('Foundation');
  const app = Application.currentApplication(); app.includeStandardAdditions = true;
  const HOME = ObjC.unwrap($.NSHomeDirectory());
  const q = s => "'" + String(s).replace(/'/g, "'\\''") + "'";
  const sh = cmd => app.doShellScript(cmd, {alteringLineEndings:false});
  const readText = p => ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null));
  const writeText = (p, t) => { if(!$(t).writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null)) throw new Error('No se pudo escribir ' + p); };
  const LOG = HOME + '/Library/Logs/EliptikaRespaldo.log';
  const log = m => { try{ sh(`printf '%s\\n' ${q(new Date().toISOString() + '  ' + m)} >> ${q(LOG)}`); }catch(e){} };
  const notify = (m, sub) => { try{ app.displayNotification(m, {withTitle:'Elíptica · Copia de seguridad', subtitle: sub || ''}); }catch(e){} };

  let tmp = null;
  try{
    const cfg = JSON.parse(readText(HOME + '/Library/Application Support/EliptikaRespaldo/config.json'));
    const pw = sh(`/usr/bin/security find-generic-password -s eliptica-respaldo -a ${q(cfg.email)} -w`).replace(/\n$/, '');
    tmp = sh('/usr/bin/mktemp -d /tmp/eliptica.XXXXXX').trim();
    sh(`chmod 700 ${q(tmp)}`);

    // 1. Iniciar sesión con el usuario de respaldo
    writeText(tmp + '/login.json', JSON.stringify({email: cfg.email, password: pw}));
    sh(`chmod 600 ${q(tmp + '/login.json')}`);
    const code = sh(`/usr/bin/curl -sS --connect-timeout 30 --retry 3 --retry-delay 20 --retry-all-errors --max-time 60 -o ${q(tmp + '/tok.json')} -w '%{http_code}' -X POST ${q(cfg.url + '/auth/v1/token?grant_type=password')} -H ${q('apikey: ' + cfg.key)} -H 'Content-Type: application/json' --data @${q(tmp + '/login.json')}`);
    sh(`rm -f ${q(tmp + '/login.json')}`);
    const tj = JSON.parse(readText(tmp + '/tok.json'));
    if(code !== '200' || !tj.access_token) throw new Error('No se pudo iniciar sesión (' + code + '): ' + (tj.error_description || tj.msg || tj.message || ''));
    writeText(tmp + '/h.txt', 'apikey: ' + cfg.key + '\nAuthorization: Bearer ' + tj.access_token + '\nAccept: application/json\n');
    sh(`chmod 600 ${q(tmp + '/h.txt')} ; rm -f ${q(tmp + '/tok.json')}`);

    // 2. Descargar la base completa, de a 1000 filas
    let rows = [];
    for(let off = 0, k = 0; ; off += 1000, k++){
      const f = tmp + '/p' + k + '.json';
      const c = sh(`/usr/bin/curl -sS --connect-timeout 30 --retry 3 --retry-delay 20 --retry-all-errors --max-time 180 -o ${q(f)} -w '%{http_code}' -H @${q(tmp + '/h.txt')} ${q(cfg.url + '/rest/v1/base_exportable?select=*&offset=' + off + '&limit=1000')}`);
      const arr = JSON.parse(readText(f));
      if(c !== '200' || !Array.isArray(arr)) throw new Error('Error al descargar (' + c + '): ' + JSON.stringify(arr).slice(0, 200));
      for(const r of arr) rows.push(r);
      if(arr.length < 1000) break;
    }
    if(!rows.length) throw new Error('La base no devolvió filas. Revisa que el usuario de respaldo tenga el rol "consulta".');

    // 3. Armar el Excel
    const parts = buildParts(rows), dir = tmp + '/x';
    for(const p in parts){
      const full = dir + '/' + p;
      sh(`mkdir -p ${q(full.slice(0, full.lastIndexOf('/')))}`);
      writeText(full, parts[p]);
    }
    const d = new Date(), pad = n => String(n).padStart(2, '0');
    const nombre = `COPIA_SEGURIDAD_${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}.xlsx`;
    sh(`cd ${q(dir)} && /usr/bin/zip -q -X -r ../out.xlsx '[Content_Types].xml' _rels xl`);
    // Copiar (no mover): las carpetas de Google Drive / iCloud no aceptan "mover" desde /tmp
    let destino = cfg.carpeta, aviso = '';
    const copiarA = (src, dir, name) => {
      sh(`mkdir -p ${q(dir)}`);
      try{ sh(`/bin/cp -X ${q(src)} ${q(dir + '/' + name)}`); }
      catch(e){ sh(`/bin/cat ${q(src)} > ${q(dir + '/' + name)}`); }
      const a = sh(`/usr/bin/stat -f %z ${q(src)}`).trim(), b = sh(`/usr/bin/stat -f %z ${q(dir + '/' + name)}`).trim();
      if(a !== b) throw new Error('El archivo copiado quedó incompleto');
    };
    const copiar = dir => copiarA(tmp + '/out.xlsx', dir, nombre);
    try{ copiar(destino); }
    catch(e){
      destino = HOME + '/Respaldos Eliptica';
      aviso = ' (no se pudo escribir en ' + cfg.carpeta + ': ' + e.message + ' — se guardó en ' + destino + ')';
      copiar(destino);
    }

    // 4. Borrar copias más viejas que N días (por defecto 60)
    try{ sh(`find ${q(destino)} -maxdepth 1 -name 'COPIA_SEGURIDAD_*.xlsx' -mtime +${Number(cfg.dias) || 60} -delete`); }catch(e){}

    // 5. Copia COMPLETA: todas las tablas de la base (órdenes de despacho, programaciones,
    //    actas con firmas, remisiones, historial, personas, usuarios…) en un .zip con un JSON por tabla.
    //    Las tablas nuevas entran solas. Si algo de esto falla, la copia en Excel ya quedó hecha.
    const fallas = []; let extra = '';
    const rpc = (fn, body, out) => {
      writeText(tmp + '/b.json', JSON.stringify(body || {}));
      const c = sh(`/usr/bin/curl -sS --connect-timeout 30 --retry 3 --retry-delay 20 --retry-all-errors --max-time 180 -o ${q(out)} -w '%{http_code}' -X POST -H @${q(tmp + '/h.txt')} -H 'Content-Type: application/json' --data @${q(tmp + '/b.json')} ${q(cfg.url + '/rest/v1/rpc/' + fn)}`);
      const txt = readText(out);
      if(c !== '200') throw new Error(fn + ' (' + c + '): ' + String(txt).slice(0, 200));
      return txt;
    };
    try{
      const tablas = JSON.parse(rpc('respaldo_tablas', {}, tmp + '/tablas.json'));
      if(!Array.isArray(tablas) || !tablas.length) throw new Error('no se recibió la lista de tablas');
      const cdir = tmp + '/completa';
      sh(`mkdir -p ${q(cdir)}`);
      const resumen = [];
      for(const t of tablas){
        const partes = []; let n = 0;
        for(let off = 0; ; off += 1000){
          const txt = rpc('respaldo_tabla', {p_tabla: t, p_desde: off, p_limite: 1000}, tmp + '/t.json').trim();
          const arr = JSON.parse(txt);
          if(!Array.isArray(arr)) throw new Error('respuesta inválida en ' + t);
          if(arr.length) partes.push(txt.slice(1, -1));
          n += arr.length;
          if(arr.length < 1000) break;
        }
        writeText(cdir + '/' + t + '.json', '[' + partes.join(',') + ']');
        resumen.push(t + ': ' + n + ' filas');
      }
      // El SQL que reconstruye la app completa (estructura, permisos, funciones) y la lista de usuarios
      let rein = false;
      try{
        const esq = JSON.parse(rpc('respaldo_esquema', {}, tmp + '/esq.json'));
        if(typeof esq !== 'string' || esq.length < 1000) throw new Error('respuesta vacía');
        writeText(cdir + '/REINSTALAR_APP.sql', esq);
        writeText(tmp + '/rein.sql', esq);
        copiarA(tmp + '/rein.sql', destino, 'REINSTALAR_APP.sql');   // suelto en la carpeta: siempre el más reciente
        writeText(cdir + '/_usuarios.json', rpc('respaldo_usuarios', {}, tmp + '/usr.json'));
        rein = true;
      }catch(e){ fallas.push('SQL de reinstalación: ' + e.message); }
      writeText(cdir + '/LEEME.txt', 'ELÍPTICA · Copia completa de la base de producción\n' + new Date().toString() + '\n\n' +
        'SI LA APP SE PIERDE (proyecto de Supabase dañado, borrado o atacado):\n' +
        '1. Crear un proyecto nuevo en Supabase.\n' +
        '2. SQL Editor → pegar REINSTALAR_APP.sql completo → Run. Eso reconstruye toda la app vacía.\n' +
        '3. Crear los usuarios (están en _usuarios.json) y cargar los datos: un .json por tabla,\n' +
        '   en el orden de abajo, con la función restaurar_tabla(); al final restaurar_secuencias().\n' +
        '   Claude puede hacer el paso 3 con este .zip.\n' +
        '4. Subir los PDF de la carpeta PDF_OP y cambiar la dirección del proyecto en la app.\n\n' +
        (rein ? '' : '¡OJO! Esta copia no trae REINSTALAR_APP.sql (falta correr el SQL 40).\n\n') +
        'Tablas, en orden de restauración:\n' + resumen.join('\n') + '\n');
      const nz = nombre.replace('COPIA_SEGURIDAD_', 'COPIA_COMPLETA_').replace(/\.xlsx$/, '.zip');
      sh(`cd ${q(cdir)} && /usr/bin/zip -q -X -r ../completa.zip .`);
      copiarA(tmp + '/completa.zip', destino, nz);
      try{ sh(`find ${q(destino)} -maxdepth 1 -name 'COPIA_COMPLETA_*.zip' -mtime +${Number(cfg.dias) || 60} -delete`); }catch(e){}
      extra += ' · ' + tablas.length + ' tablas';
    }catch(e){ fallas.push('tablas: ' + e.message); }

    // 6. PDF de las OP: baja solo los nuevos o cambiados a la carpeta PDF_OP.
    //    Nunca borra: si un PDF se reemplaza en la app, el anterior queda guardado con la fecha.
    try{
      const lista = JSON.parse(rpc('respaldo_pdfs', {}, tmp + '/pdfs.json'));
      const pdir = destino + '/PDF_OP', idx = pdir + '/indice.json';
      sh(`mkdir -p ${q(pdir)}`);
      let man = {};
      try{ man = JSON.parse(readText(idx)) || {}; }catch(e){ man = {}; }
      writeText(tmp + '/h2.txt', readText(tmp + '/h.txt').replace(/Accept:[^\n]*\n/, ''));
      const existe = f => { try{ sh(`test -f ${q(f)}`); return true; }catch(e){ return false; } };
      let nuevos = 0, errores = 0;
      for(const o of lista){
        const local = pdir + '/' + o.name;
        if(man[o.name] === o.updated_at && existe(local)) continue;
        const enc = o.name.split('/').map(encodeURIComponent).join('/');
        const c = sh(`/usr/bin/curl -sS --connect-timeout 30 --retry 3 --retry-delay 20 --retry-all-errors --max-time 180 -o ${q(tmp + '/pdf.bin')} -w '%{http_code}' -H @${q(tmp + '/h2.txt')} ${q(cfg.url + '/storage/v1/object/authenticated/ordenes/' + enc)}`);
        if(c !== '200'){ errores++; continue; }
        const sub = local.slice(0, local.lastIndexOf('/'));
        if(existe(local)){   // cambió en la app: guardar la versión anterior
          const d2 = new Date(), p2 = n => String(n).padStart(2, '0');
          const viejo = local.replace(/\.pdf$/i, '') + ` (anterior ${d2.getFullYear()}-${p2(d2.getMonth()+1)}-${p2(d2.getDate())}).pdf`;
          try{ sh(`/bin/mv -f ${q(local)} ${q(viejo)}`); }catch(e){}
        }
        copiarA(tmp + '/pdf.bin', sub, local.slice(local.lastIndexOf('/') + 1));
        man[o.name] = o.updated_at; nuevos++;
        if(nuevos % 25 === 0) writeText(idx, JSON.stringify(man));
      }
      writeText(idx, JSON.stringify(man));
      extra += ' · ' + lista.length + ' PDF' + (nuevos ? ' (' + nuevos + (nuevos === 1 ? ' nuevo)' : ' nuevos)') : '');
      if(errores) fallas.push(errores + ' PDF no se pudieron bajar');
    }catch(e){ fallas.push('PDF: ' + e.message); }

    // 7. Anotar la copia en la app (aparece en el aviso del gerente)
    writeText(tmp + '/r.json', JSON.stringify({p_origen: 'mac', p_filas: rows.length}));
    sh(`/usr/bin/curl -sS --connect-timeout 30 --retry 3 --retry-delay 20 --retry-all-errors --max-time 60 -o /dev/null -X POST -H @${q(tmp + '/h.txt')} -H 'Content-Type: application/json' --data @${q(tmp + '/r.json')} ${q(cfg.url + '/rest/v1/rpc/registrar_respaldo')}`);

    const falla = fallas.length ? ' · AVISO: ' + fallas.join(' | ') : '';
    log((fallas.length ? 'PARCIAL ' : 'OK ') + rows.length + ' filas' + extra + ' -> ' + destino + '/' + nombre + aviso + falla);
    if(fallas.length) notify('Excel guardado, pero falló una parte: ' + fallas.join(' | '), 'Envíale este aviso a Claude');
    else notify(rows.length.toLocaleString('es-CO') + ' registros' + extra + (aviso ? ' en Respaldos Eliptica' : ''), nombre);
    return (fallas.length ? 'PARCIAL ' : 'OK ') + rows.length + ' filas' + extra + ' -> ' + destino + '/' + nombre + aviso + falla;
  }catch(e){
    log('ERROR (intento ' + intento + ' de ' + total + ') ' + e.message);
    if(intento >= total) notify('No se pudo hacer la copia: ' + e.message, 'Revisa el registro en Consola');
    throw e;
  }finally{
    if(tmp) try{ sh(`rm -rf ${q(tmp)}`); }catch(e){}
  }
}
EOF_JS
echo "✓ Copia de seguridad actualizada"
echo ""
echo "Haciendo una copia de prueba… (la primera vez baja todos los PDF y puede tardar varios minutos)"
ANTES=$(wc -l < "$LOG" 2>/dev/null || echo 0)
launchctl kickstart -k "gui/$(id -u)/$LABEL"
for i in {1..180}; do
  sleep 5
  NUEVO=$(tail -n +$((ANTES+1)) "$LOG" 2>/dev/null | grep -E "OK |PARCIAL |ERROR \(intento 3" | tail -1 || true)
  [[ -n "$NUEVO" ]] && break
done
echo ""
if [[ "$NUEVO" == *"OK "* ]]; then
  echo "✓ LISTO. $NUEVO"
elif [[ -n "$NUEVO" ]]; then
  echo "✗ Algo no funcionó: $NUEVO"
  echo ""
  echo "Copia este mensaje y envíaselo a Claude."
else
  echo "La copia sigue trabajando en segundo plano. Al terminar verás una notificación."
fi
