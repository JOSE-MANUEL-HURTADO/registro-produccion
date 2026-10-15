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
function run(argv){
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
    const code = sh(`/usr/bin/curl -sS --max-time 60 -o ${q(tmp + '/tok.json')} -w '%{http_code}' -X POST ${q(cfg.url + '/auth/v1/token?grant_type=password')} -H ${q('apikey: ' + cfg.key)} -H 'Content-Type: application/json' --data @${q(tmp + '/login.json')}`);
    sh(`rm -f ${q(tmp + '/login.json')}`);
    const tj = JSON.parse(readText(tmp + '/tok.json'));
    if(code !== '200' || !tj.access_token) throw new Error('No se pudo iniciar sesión (' + code + '): ' + (tj.error_description || tj.msg || tj.message || ''));
    writeText(tmp + '/h.txt', 'apikey: ' + cfg.key + '\nAuthorization: Bearer ' + tj.access_token + '\nAccept: application/json\n');
    sh(`chmod 600 ${q(tmp + '/h.txt')} ; rm -f ${q(tmp + '/tok.json')}`);

    // 2. Descargar la base completa, de a 1000 filas
    let rows = [];
    for(let off = 0, k = 0; ; off += 1000, k++){
      const f = tmp + '/p' + k + '.json';
      const c = sh(`/usr/bin/curl -sS --max-time 180 -o ${q(f)} -w '%{http_code}' -H @${q(tmp + '/h.txt')} ${q(cfg.url + '/rest/v1/base_exportable?select=*&offset=' + off + '&limit=1000')}`);
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
    const src = tmp + '/out.xlsx';
    let destino = cfg.carpeta, aviso = '';
    const copiar = dir => {
      sh(`mkdir -p ${q(dir)}`);
      try{ sh(`/bin/cp -X ${q(src)} ${q(dir + '/' + nombre)}`); }
      catch(e){ sh(`/bin/cat ${q(src)} > ${q(dir + '/' + nombre)}`); }
      const a = sh(`/usr/bin/stat -f %z ${q(src)}`).trim(), b = sh(`/usr/bin/stat -f %z ${q(dir + '/' + nombre)}`).trim();
      if(a !== b) throw new Error('El archivo copiado quedó incompleto');
    };
    try{ copiar(destino); }
    catch(e){
      destino = HOME + '/Respaldos Eliptica';
      aviso = ' (no se pudo escribir en ' + cfg.carpeta + ': ' + e.message + ' — se guardó en ' + destino + ')';
      copiar(destino);
    }

    // 4. Borrar copias más viejas que N días (por defecto 60)
    try{ sh(`find ${q(destino)} -maxdepth 1 -name 'COPIA_SEGURIDAD_*.xlsx' -mtime +${Number(cfg.dias) || 60} -delete`); }catch(e){}

    // 5. Anotar la copia en la app (aparece en el aviso del gerente)
    writeText(tmp + '/r.json', JSON.stringify({p_origen: 'mac', p_filas: rows.length}));
    sh(`/usr/bin/curl -sS --max-time 60 -o /dev/null -X POST -H @${q(tmp + '/h.txt')} -H 'Content-Type: application/json' --data @${q(tmp + '/r.json')} ${q(cfg.url + '/rest/v1/rpc/registrar_respaldo')}`);

    log('OK ' + rows.length + ' filas -> ' + destino + '/' + nombre + aviso);
    notify(rows.length.toLocaleString('es-CO') + ' registros guardados' + (aviso ? ' en Respaldos Eliptica' : ''), nombre);
    return 'OK ' + rows.length + ' filas -> ' + destino + '/' + nombre + aviso;
  }catch(e){
    log('ERROR ' + e.message);
    notify('No se pudo hacer la copia: ' + e.message, 'Revisa el registro en Consola');
    throw e;
  }finally{
    if(tmp) try{ sh(`rm -rf ${q(tmp)}`); }catch(e){}
  }
}
