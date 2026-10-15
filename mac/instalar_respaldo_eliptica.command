#!/bin/zsh
# ════════════════════════════════════════════════════════════════
#  ELÍPTICA · Instalador de la copia de seguridad automática (Mac)
#  Uso: abre Terminal y escribe   zsh ~/Downloads/instalar_respaldo_eliptica.command
# ════════════════════════════════════════════════════════════════
set -e
URL="https://fnwndrdebndlirmejlgb.supabase.co"
KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZud25kcmRlYm5kbGlybWVqbGdiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NDcxNzUsImV4cCI6MjEwNzUyMzE3NX0.zoTCGcjrsH3is2sQZEsGKkWpB_d_70dMEIJ1SySBges"
DIR="$HOME/Library/Application Support/EliptikaRespaldo"
PLIST="$HOME/Library/LaunchAgents/co.eliptica.respaldo.plist"
LOG="$HOME/Library/Logs/EliptikaRespaldo.log"
LABEL="co.eliptica.respaldo"

pregunta(){ osascript -e "text returned of (display dialog \"$1\" default answer \"$2\" with title \"Elíptica · Copia de seguridad\")"; }

echo ""
echo "  ELÍPTICA · Copia de seguridad automática"
echo "  ─────────────────────────────────────────"
echo ""

# 1. Usuario de respaldo
EMAIL=$(pregunta "Correo del usuario de respaldo (creado en Supabase con rol consulta):" "respaldo@eliptica.com.co")
[[ -z "$EMAIL" ]] && { echo "Cancelado."; exit 1; }
echo "Escribe la contraseña de $EMAIL (no se verá al escribir) y pulsa Enter. Te la pedirá dos veces."
security delete-generic-password -s eliptica-respaldo -a "$EMAIL" >/dev/null 2>&1 || true
security add-generic-password -s eliptica-respaldo -a "$EMAIL" -l "Elíptica respaldo" -T /usr/bin/security -w
echo "✓ Contraseña guardada en el Llavero del Mac"

# 2. Carpeta
DEF="$HOME/Respaldos Eliptica"
BTN=$(osascript -e "button returned of (display dialog \"¿Dónde guardo las copias?\n\nRecomendado: $DEF\n\nEvita Escritorio, Documentos y Descargas: macOS puede bloquear que una tarea automática escriba allí.\" buttons {\"Elegir otra carpeta…\", \"Usar la recomendada\"} default button 2 with title \"Elíptica · Copia de seguridad\")")
if [[ "$BTN" == "Usar la recomendada" ]]; then CARPETA="$DEF"; else
  CARPETA=$(osascript -e 'POSIX path of (choose folder with prompt "Carpeta para las copias de seguridad")'); CARPETA="${CARPETA%/}"; fi
mkdir -p "$CARPETA"
echo "✓ Carpeta: $CARPETA"

# 3. Hora
HORA=$(pregunta "¿A qué hora se hace la copia cada día? (formato 24 h, ej. 19:00)" "19:00")
H=${HORA%%:*}; M=${HORA##*:}; H=$((10#$H)); M=$((10#${M:-0}))
DIAS=$(pregunta "¿Cuántos días guardo las copias antes de borrar las viejas?" "60")

# 4. Archivos
mkdir -p "$DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
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
    sh(`mkdir -p ${q(cfg.carpeta)} && mv ${q(tmp + '/out.xlsx')} ${q(cfg.carpeta + '/' + nombre)}`);

    // 4. Borrar copias más viejas que N días (por defecto 60)
    sh(`find ${q(cfg.carpeta)} -maxdepth 1 -name 'COPIA_SEGURIDAD_*.xlsx' -mtime +${Number(cfg.dias) || 60} -delete`);

    // 5. Anotar la copia en la app (aparece en el aviso del gerente)
    writeText(tmp + '/r.json', JSON.stringify({p_origen: 'mac', p_filas: rows.length}));
    sh(`/usr/bin/curl -sS --max-time 60 -o /dev/null -X POST -H @${q(tmp + '/h.txt')} -H 'Content-Type: application/json' --data @${q(tmp + '/r.json')} ${q(cfg.url + '/rest/v1/rpc/registrar_respaldo')}`);

    log('OK ' + rows.length + ' filas -> ' + nombre);
    notify(rows.length.toLocaleString('es-CO') + ' registros guardados', nombre);
    return 'OK ' + rows.length + ' filas -> ' + cfg.carpeta + '/' + nombre;
  }catch(e){
    log('ERROR ' + e.message);
    notify('No se pudo hacer la copia: ' + e.message, 'Revisa el registro en Consola');
    throw e;
  }finally{
    if(tmp) try{ sh(`rm -rf ${q(tmp)}`); }catch(e){}
  }
}
EOF_JS
cat > "$DIR/config.json" <<EOF_CFG
{"url":"$URL","key":"$KEY","email":"$EMAIL","carpeta":"$CARPETA","dias":${DIAS:-60}}
EOF_CFG
chmod 600 "$DIR/config.json"

cat > "$PLIST" <<EOF_PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/osascript</string><string>-l</string><string>JavaScript</string><string>$DIR/respaldo.js</string>
  </array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>$H</integer><key>Minute</key><integer>$M</integer></dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF_PL

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
printf "✓ Programada todos los días a las %02d:%02d\n" $H $M

# 5. Primera copia de prueba (corre igual que la automática)
echo ""
echo "Haciendo la primera copia de prueba… (puede tardar 1 o 2 minutos)"
ANTES=$(wc -l < "$LOG" 2>/dev/null || echo 0)
launchctl kickstart -k "gui/$(id -u)/$LABEL"
for i in {1..90}; do
  sleep 2
  NUEVO=$(tail -n +$((ANTES+1)) "$LOG" 2>/dev/null | grep -E "OK |ERROR" | tail -1)
  [[ -n "$NUEVO" ]] && break
done
echo ""
if [[ "$NUEVO" == *"OK "* ]]; then
  echo "✓ LISTO. $NUEVO"
  open "$CARPETA"
else
  echo "✗ La copia de prueba no funcionó:"
  tail -n 5 "$LOG" 2>/dev/null
  echo ""
  echo "Copia este mensaje y envíaselo a Claude."
fi
echo ""
echo "Para desinstalar:  launchctl bootout gui/\$(id -u)/$LABEL ; rm \"$PLIST\""
