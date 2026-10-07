export const labels = { waiting:'En attente',offered:'Place proposée',active:'En pause',completed:'Terminée',cancelled:'Annulée',expired:'Proposition expirée' };
export function duration(ms) { const seconds=Math.max(0,Math.ceil(Math.abs(ms)/1000)); return `${Math.floor(seconds/60)}:${String(seconds%60).padStart(2,'0')}`; }
export function csvCell(value) { let text=String(value??''); if (/^[\s]*[=+@-]/.test(text)) text="'"+text; return '"'+text.replaceAll('"','""')+'"'; }
export function csv(rows) {
 const fields=['display_name','team_name','requested_at','started_at','due_at','ended_at','status','reason'];
 const headers=['Conseiller','Équipe','Demande (UTC)','Départ (UTC)','Fin prévue (UTC)','Retour (UTC)','État','Motif'];
 return '\uFEFF'+[headers,...rows.map(r=>fields.map(f=>f==='status'?(labels[r[f]]||r[f]):r[f]))].map(r=>r.map(csvCell).join(';')).join('\r\n');
}
export function metrics(rows) {
 const departed=rows.filter(r=>r.started_at),completed=departed.filter(r=>r.ended_at);
 return { requests:rows.length,completed:completed.length,averageWait:departed.length?departed.reduce((sum,r)=>sum+Date.parse(r.started_at)-Date.parse(r.requested_at),0)/departed.length:0,overdue:completed.filter(r=>Date.parse(r.ended_at)>Date.parse(r.due_at)).length };
}
export function serialQueue() { let tail=Promise.resolve(); return fn=>{const result=tail.then(fn);tail=result.catch(()=>{});return result;}; }
