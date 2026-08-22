# Piano di lavoro — extractionengine

**Stato:** consolidato dopo quattro round di review e una verifica supplementare
del piano corrente.
**Base:** `phase-0-cleanup` @ `7b06af5`.
**Data:** 2026-08-21.

Le affermazioni marcate *[misurato]* sono state riprodotte eseguendo il pacchetto
sotto R 4.6.1. Quelle marcate *[verificato]* sono state lette nel sorgente **da
chi scrive questo documento**, non riprese da un revisore. La distinzione non è
pedanteria: un'affermazione ereditata da un revisore e timbrata come verificata è
già finita due volte in questo piano, ed era falsa entrambe le volte.

---

## Il giudizio di fondo

> **Il contratto è giusto, la macchina è sbagliata.**

I round di review convergono su questo. I tre livelli di authoring
(`concept_spec` → `use_channel` → output), l'idea che le relazioni fra chiavi si
**dichiarano** invece di essere dedotte, il rifiuto di dedurre l'assenza clinica
dal silenzio della fonte, e la disciplina sulle risposte LLM — quelle sono le
decisioni costose da invertire, e sono corrette. Nessuno propone di rifarle.

Quello che va rifatto è il motore che le esegue.

---

## Parte 1 — Decisioni chiuse

Sei decisioni prese durante i round 2 e 3. Entrambi i revisori del round 3 hanno
provato a riaprirle e non ci sono riusciti. **Non si ridiscutono.**

**1. Un combine cross-source su `ELTID` è privo di senso, non solo vuoto.**
`by` nomina la chiave su cui l'espressione viene valutata come un unico
predicato. Due sorgenti non possono mai posare un segnale sullo stesso elemento.
Il divieto resta; la motivazione scritta nel codice va corretta (§Fase 1.9).
Un combine a `ELTID` fra alias della **stessa sorgente** resta invece legittimo:
per esempio potassio e sodio richiesti sullo stesso prelievo biologico.

**2. Le etichette di copertura strutturata spariscono.**
Il motore non può sapere se "tachicardia" manca perché il paziente non ce
l'aveva, perché è stato usato un sinonimo, perché non è stata valutata, o perché
è stata valutata e non scritta. Quel limite è irriducibile. Per un esecutore
strutturato fail-fast, una run restituita dice già che il motore ha eseguito
quanto richiesto; un errore interrompe la run e non diventa una riga `error`.
`complete`, `partial` e `no_candidate` non fanno parte del contratto pubblico
desiderato. I fatti operativi restano come righe e conteggi, non come etichette
epistemiche.

**3. Anche il laboratorio non produce negativi accertati.**
Un laboratorio misura in istanti discreti. Quaranta potassiemie sotto 6
significano "non sopra 6 nei momenti campionati". Quindi non serve un'algebra
diversa per il laboratorio: servono gli stessi fatti operativi, senza una
tassonomia di copertura separata.

**4. Il roster si costruisce dalle sorgenti passate alla run**, una volta, ed è
condiviso da tutte le variabili di quella run. Conserva però l'appartenenza alla
sorgente: a `ELTID` l'universo di un combine resta nel dominio della sorgente
partecipante, così elementi di biologia non entrano nel complemento di un canale
documentale.

> **Roster** = l'elenco di *quali unità esistono* a un dato livello — quali
> pazienti, quali degenze, quali elementi. Serve per rispondere alle domande al
> negativo: per dire *"questa degenza non ha X"* devi prima sapere che quella
> degenza esiste. Oggi il motore non ha un elenco simile e si arrangia guardando
> dove ha trovato qualcosa, che è il difetto B.

Il motore cerca in ogni unità per cui ha dati; non può sapere delle unità che non
ha mai ricevuto, e non deve fingere di saperlo. È l'equivalente di un indice
Lucene: un universo esplicito e stabile che esiste prima della query.

**5. Ci sono quattro dichiarazioni relazionali distinte, e solo tre si possono
scrivere**: `search_within` (dove il motore può guardare), `combine$by`,
`filter_by_qualified`, `output$group_by`. La prima è quella che oggi manca per i
canali strutturati, ed è la dichiarazione mancante di tutto il piano.

**6. Il divieto di `search_within` sui canali strutturati va tolto.**

Oggi `search_within` è vietato per i canali strutturati, e da nessuna parte è
scritto perché. *[verificato: `R/spec.R:416-420` contro `R/run_variable.R:640-659`]*
Nel frattempo `.channel_scope_keys()` lo onora già correttamente se lo trova: il
divieto è nel costruttore, la capacità è già nell'esecutore.

**La decisione è di rimuoverlo**, e di andare oltre: `search_within` diventa
**obbligatorio** anche per i canali strutturati, come già lo è per quelli di
testo. Il vocabolario ammesso resta `PATID`, `EVTID`. `ELTID` resta invece una
chiave legittima di combine fra alias della stessa sorgente; non è uno scope di
ricerca finché non esiste un consumatore reale a grain elemento. È la Fase 2.

---

## Parte 2 — I difetti confermati

| | Difetto | Chi l'ha trovato | Conseguenza |
|---|---|---|---|
| **A1** | Scope non dichiarabile — la coorte | Opus, round 2 | Il valore pubblicato di un ricovero cambia a seconda di quali *altri* ricoveri sono nella coorte. **Nessuna finestra dichiarata da nessuna parte.** Etichetta: `complete`. |
| **A2** | Scope non dichiarabile — la finestra | Opus, round 2 | Una finestra che non esclude niente ribalta la risposta, perché dichiarare una finestra sposta lo scope dal grain di output a `PATID`. Etichetta: `complete`. |
| **B** | Il complemento del combine non ha un universo | entrambi, round 1 | Fine→coarse costruisce l'universo dalle sole evidenze positive. Criterio esatto: **non valido esattamente quando `f(FALSE,…,FALSE) = TRUE`** — quindi anche `a \| !b`, non solo la negazione pura. |
| **C** | Lo stesso stato viene rimappato diversamente a valle | Opus, round 1 + review finale | `no_candidate` diventa `complete` nel percorso membership e `partial` nel percorso `from_channel`: la divergenza è negli assemblatori, non soltanto nei vocabolari degli esecutori. |
| **D** | Il data mask ricade sul workspace del chiamante | Opus, round 2 | `mean(NUMRE5)` con `NUMRE5 <- -1` in sessione pubblica `-1`, copertura `complete`, con righe di evidenza di laboratorio vere allegate. |
| **E** | Esecuzione ansiosa | GPT, round 1 | Il payload gira per tutti i task prima del gate. Con un gate al 10% su 100 000 degenze: fino a 100 000 chiamate al modello per scartarne 90 000. |
| **F** | Runtime quadratico, memoria ~9× | entrambi | *[misurato]* 25,5 MB restituiti su 2,8 MB di sorgente, una variabile. Un protocollo da 40 variabili a 20 000 pazienti restituirebbe ~10 GB in memoria. |
| **G** | Provider e modello cablati su Ollama | entrambi | `APPROVED_MODELS <- c("gemma3:4b")` è una policy di governance dentro una costante di pacchetto. Contraddice "ellmer possiede il transport". |
| **H** | Superficie morta | Opus, round 1 | Quattro campi/funzioni mai letti (`native_grain`, `produces`, `act_channel`, `derivation`) **e**, separatamente, quattro funzioni esportate (`source_spec` e compagne) che l'esecuzione non può consumare. |
| **I** | I semplici parametri `.env` non sono fotografati | HANDOFF + review finale | `NUMRES < .env$soglia` lascia lo stesso manifest con `soglia = 12` e `soglia = 13`. La Fase 5 deve registrare il valore semplice effettivamente usato, senza serializzare funzioni o l'intera sessione R. |
| **J** | Esecuzione dei canali per variabile | Opus, round 1 | N variabili sullo stesso canale = N esecuzioni. |
| **K** | Due rami di default fabbricano stati | Opus, round 2 | Un task assente diventa `no_eligible_source` per default, non per errore. |

A1 e A2 sono **due meccanismi distinti**, non due sintomi dello stesso. Vengono
dalle due inferenze che stanno sulla stessa riga:

```r
if (is.null(channel_def$window)) grain_keys else "PATID"   # R/run_variable.R:658
#  ^--- questo ramo produce A1              ^--- questo produce A2
```

Una riparazione che tocca solo il secondo ramo lascia A1 completamente intatto.
*[misurato]* su questo checkout, senza nessuna finestra dichiarata: la degenza E1
di P1 pubblica `0` con coorte `{E1}` e `1` con coorte `{E1,E2}`, entrambe
`channel_coverage = complete`; iniettando `search_within = "PATID"` diventa `1` in
tutti e due i casi.

---

## Parte 3 — Il piano

### Fase 0 — rete di sicurezza, **senza dati di pazienti**

**La decisione: usare un comparatore prima/dopo su soli dati sintetici.** Non è un
oracolo di verità clinica: risponde soltanto a *"questa modifica ha cambiato il
comportamento osservabile sugli stessi input?"*.

In `outputs/differential-oracle/` esiste già uno scaffold con:

- piccoli casi sintetici per laboratorio, combine, testo/LLM e date documentali;
- un fake del modello;
- due runner e un confronto `all.equal()`.

Non è però pronto all'uso. *[verificato]* i runner referenziano fixture ritirate,
la normalizzazione usa ancora nomi obsoleti come `grain_id`, e
`normalize_frame()` restituisce `data.frame()` quando nessuna colonna attesa è
presente. Due envelope entrambe incompatibili possono quindi risultare uguali:
una rete verde che non confronta nulla.

Gli `old.rds`/`new.rds` presenti dimostrano soltanto che lo scaffold ha girato a
luglio; il loro confronto verde non è una baseline del checkout corrente. Le
fotografie vanno rigenerate dopo aver riparato il runner.

**Lavoro della Fase 0:**

1. recuperare dalle fixture ritirate soltanto le piccole `tibble()` sintetiche, i
   costruttori necessari e `helper-fake-chat.R`; **non** recuperare le loro
   aspettative né i vecchi commenti epistemici;
2. aggiornare l'envelope al contratto pubblico corrente;
3. rendere la normalizzazione fail-fast: se manca una colonna dichiarata come
   necessaria al confronto, il runner fallisce invece di produrre un frame vuoto;
4. generare la fotografia *prima* dal checkout di base e confrontarla con la
   fotografia *dopo* ogni intervento.

Lo strumento sintetico deve vivere in una posizione versionabile fuori da
`outputs/`; gli snapshot e gli artefatti temporanei possono restare in `outputs/`.
La promozione a test permanente o a CI si decide solo se, finita la riscrittura,
continua a custodire un contratto utile. Non si ricostruisce una suite generale.

**Nessun artefatto derivato da pazienti è una baseline.** I run reali di giugno e
luglio restano ignorati e fuori da questo lavoro.

Regole del confronto:

- Si confrontano **chiavi identificative, valori, stato operativo pubblico e
  insieme ordinato dei riferimenti di evidenza** realmente presenti nel contratto
  corrente.
- Il set di fixture contiene almeno un task `from_channel()` senza righe di
  payload. Il confronto deve verificare che la riga del task non sparisca, che il
  valore resti mancante e che gli stati operativi pubblici restino invariati:
  l'universo viene dai task dichiarati, non dai soli gruppi presenti nei dati.
- `channel_coverage` non viene elevato a baseline: la Fase 3 lo elimina dai
  risultati strutturati.
- I casi colpiti dal difetto B vengono identificati meccanicamente con il criterio
  della guardia (`f(FALSE,…,FALSE) = TRUE` e
  `rank(combine$by) > rank(output$group_by)`) e tracciati a parte: prima
  restituiscono un valore sbagliato, dopo la Fase 1.2 devono fallire al build. Non
  entrano nel confronto di uguaglianza per una selezione fatta a occhio.

Nella Fase 1, salvo l'errore intenzionale introdotto dalla guardia del difetto B,
**un diff è un errore**. Dalla Fase 2 in poi alcuni cambiamenti sono intenzionali:
il diff diventa l'elenco concreto delle variabili da riesaminare, non un verdetto
automatico.

---

### Fase 1 — economico, alto valore, nessun cambio di semantica

In ordine di rapporto beneficio/rischio.

**1.1 — Vettorizzare gli assemblatori per task**

*[misurato]* su una variabile di semplice appartenenza — un `code_channel` su
`pmsi_diag`, `bin_output(group_by = "PATID")`, 2 000 pazienti, 20 000 righe:

| | quota del run totale |
|---|---|
| `measure_code_presence` — l'esecutore, **inclusa** l'asserzione | **2,1 %** |
| `.single_membership_variable` — assemblaggio | **97,3 %** |
| ⤷ `.channel_status_row` (`R/run_variable.R:833`) | **47,0 %** |
| ⤷ `.reduce_channel_result` (`R/channel-combine.R:56`) | **20,8 %** |

Sono due cicli `for (tid in task_ids)` che riscorrono `result$coverage`,
`result$candidates` e `result$evidence` una volta per task e allocano una tibble
di una riga per task. Un `left_join` più uno `split()` li vettorizza.

Un secondo profilo indipendente, stessa forma di variabile, dà 89,9 % / 42,5 % /
19,0 %: percentuali un po' diverse, stessa conclusione con ampio margine.

**Il costo dominante è l'allocazione, non la riscansione.** Le due misure sopra
dicono *dove sta il tempo*; questa dice *perché*. Guardando i tempi propri di ogni
chiamata, il 79 % del totale sta sotto `tibble::tibble()`, mentre le funzioni che
riscorrono le tabelle — `.state_for_task()` e `.task_candidate_count()` — a questa
dimensione quasi non si vedono.

Quindi il guadagno viene soprattutto dal **non allocare una tibble per task**, e
solo in second'ordine dal join. Una riparazione che tiene il ciclo e ci infila
dentro un join non prende né l'uno né l'altro.

**Una cosa da stabilire prima di scrivere il join.** `.reduce_channel_result()`
oggi non fa una lookup per task: prende **il primo match**.

```r
state <- cov$processing_state[cov$task_id == tid]
state <- if (length(state)) state[[1]] else "no_eligible_source"   # channel-combine.R:70-71
```

Un `left_join` è equivalente **solo se `coverage` e `values` hanno una riga per
task**. Oggi è vero per tutti e quattro i percorsi, ma per ragioni diverse e
**nessuna è asserita da nessuna parte**: per i tre esecutori strutturati per
costruzione (`coverage` discende da `tkeys` con left join su frame unici per task,
`values` ne è un `filter()`); per il percorso testo/LLM perché `attempts` accumula
esattamente una riga per task con i retry collassati in `n_tries`
*[`R/extract.R:590`, `:469`]*.

**Stabilire l'invariante, non riprodurre il `[[1]]`.** Un
`stopifnot(!anyDuplicated(cov$task_id))` costa una riga e dice cosa il codice già
assume; un `slice_head()` conserverebbe un incidente. Senza questa frase, chi
scrive il join senza aver letto `R/extract.R` fa esplodere le righe sul percorso
LLM in silenzio.

**Nessun cambio di contratto, nessuna dipendenza da nient'altro nel piano.** È il
rapporto beneficio/rischio più alto di tutti e quattro i round, e nella versione
precedente del piano non stava in nessuna fase.

**Anche `.single_from_channel_variable()` rientra nel punto 1.1.** Un benchmark
indipendente su un canale strutturato numerico, cinque righe di payload per task,
confronta l'implementazione corrente con un prototipo che partiziona il payload
una volta e assembla valori e stati senza tibble di una riga:

| task | righe payload | corrente | prototipo | speedup |
|---:|---:|---:|---:|---:|
| 500 | 2 500 | 1,23 s | 0,07 s | 17,6× |
| 1 000 | 5 000 | 2,46 s | 0,14 s | 17,6× |
| 2 000 | 10 000 | 5,29 s | 0,30 s | 17,6× |
| 4 000 | 20 000 | 9,34 s | 0,55 s | 17,0× |

*[misurato]* a 2 000 task le allocazioni transitorie cumulate scendono da
295,5 MB a 3,2 MB; il risultato restituito resta 3,01 MB in entrambi i casi. Gli
output sono identici, attributi compresi, per il caso numerico popolato provato.

Non è lo stesso fix di tre righe: l'espressione arbitraria di valore deve ancora
essere valutata **una volta per task**. Vanno eliminate invece la scansione
ripetuta dell'intero payload e le tibble di una riga per valore e stato. Il
prototipo è evidenza per includere il percorso, non codice pronto: durante
l'implementazione vanno conservati i casi vuoti e i tipi misti; il `ptype`
obbligatorio della Fase 2 chiuderà poi il contratto di tipo. Questa misura prova
il costo transitorio del ciclo, non che esso sia la causa dei 25,5 MB trattenuti
dal risultato completo.

**1.2 — Una guardia che rifiuta le variabili colpite dal difetto B**

Non ripara il difetto: lo **rende visibile**. Trasforma ogni risposta
silenziosamente sbagliata di quella classe in un errore che compare quando scrivi
la variabile, prima ancora di eseguirla.

Il test è: prendi l'espressione così com'è scritta, valutala **facendo finta che
nessun canale abbia trovato niente**. Se il risultato è TRUE, allora esistono
unità che dovrebbero qualificarsi *proprio perché non hanno evidenza* — ed è
esattamente il caso in cui il motore oggi non le vede, perché costruisce l'elenco
delle unità a partire da dove ha trovato qualcosa. Se in più `combine$by` è più
fine di `output$group_by`, rifiuta.

Tre righe in `resolve_variable_spec()`, dove `combine$ast`, `combine$by` e
`output$group_by` sono già tutti a disposizione, accanto a
`.check_eltid_identity_domain()` che ha esattamente la stessa forma.
*[verificato: `R/spec.R:833-854`]*

*[misurato]* su dieci espressioni: rifiuta `!a & !b`, `a | !b`, `!a | b`,
`!(a|b)` a EVTID→PATID; lascia passare `a & !b`, `a | b`, e tutto a grain uguale
o più grosso. Nessuno dei due revisori è riuscito a costruire un caso che le
sfugga dentro la classe dichiarata.

Si cancella il giorno in cui arriva il roster vero.

**1.3 — Chiudere il buco del data mask (difetto D)**

Il problema: se sbagli a scrivere il nome di una colonna e per caso esiste una
variabile con quel nome nella tua sessione R, il motore usa **quella** invece di
darti errore. *[misurato]* con `NUMRE5 <- -1` in sessione, `mean(NUMRE5)` — un
refuso per `NUMRES` — pubblica `-1` come valore della variabile, con copertura
`complete` e righe di evidenza di laboratorio vere allegate. L'evidenza dice che
quelle righe sostengono `-1`.

La riparazione: **un nome nudo significa sempre una colonna**; per leggere dalla
sessione devi scrivere `.env$nome` esplicitamente.

**Attenzione: non è una cancellazione pura.** *[misurato]* simulando una
cancellazione letterale del ramo che guarda la sessione, qualunque funzione
passata *come valore* diventa una "colonna mancante":

| espressione | oggi | dopo la cancellazione letterale |
|---|---|---|
| `mean(NUMRES)` | `NUMRES` | `NUMRES` |
| `vapply(split(NUMRES, ELTID), mean, numeric(1))` | `NUMRES, ELTID` | `NUMRES, ELTID, `**`mean`** |
| `mean(NUMRES, na.rm = T)` | `NUMRES` | `NUMRES, `**`T`** |
| ``Reduce(`+`, NUMRES)`` | `NUMRES` | `NUMRES, `**`+`** |

`vapply(split(NUMRES, ELTID), mean, ...)` è l'idioma "media delle medie per
ricovero" che il README rimanda esplicitamente. Smetterebbe di compilare.

La regola giusta è **una sottrazione più una condizione**: un nome trovato nella
sessione viene ignorato — cioè non conta come colonna richiesta — **solo se è una
funzione**. `exists(name, envir = env, mode = "function", inherit = TRUE)`.

Così `mean` passato come argomento resta una funzione e non dà fastidio, mentre
`NUMRE5 <- -1` viene beccato.

*[verificato]* quella regola segnala `HEIGHT <- 999` e `NUMRE5 <- -1` e lascia
passare `mean`, `median`, `` `+` ``. `T` viene segnalato, il che è corretto
perché `T` è ridefinibile, ma è un cambio di comportamento da registrare creando
`NEWS.md` quando si implementa 1.3: `na.rm = T` è comune e va riscritto
`na.rm = TRUE`.

Il punto 1.3 chiude soltanto il data mask. `.env$nome` resta l'escape hatch
esplicita per un valore esterno; le funzioni restano normale codice di authoring.
Non promette di fotografare o rendere riproducibile l'intera sessione R.

**1.4 — Dichiarare il confine del manifest fino alla Fase 5**

Il manifest continua a salvare il testo delle espressioni. Non serializza funzioni
locali, closure, active binding o altri oggetti arbitrari raggiungibili dalla
quosure. Il codice e le funzioni di authoring devono vivere in file versionati;
il manifest non è una capsula di replay dell'ambiente R.

Un semplice parametro di configurazione è però un caso diverso. Se
`NUMRES < .env$soglia` cambia risultato quando `soglia` passa da 12 a 13, il
manifest audited deve distinguere le due run. Il requisito è già concreto, ma
non giustifica plumbing provvisorio nella Fase 1. La Fase 5 fotografa una volta,
prima dell'esecuzione, i soli valori `.env$nome` semplici e serializzabili; calcolo
e manifest usano la stessa fotografia. Non si costruisce un sistema generale di
serializzazione dell'ambiente.

**1.5 — Cancellare `.assert_evidence_resolves()`**

*[verificato]* è tautologica, non solo lenta. `.validate_structured_inputs()`
asserisce l'unicità di `task_id` e `source_row_id` prima di qualunque lavoro
dell'esecutore; `observations` è un inner join di quei due, quindi la coppia è
unica per costruzione e ogni riga di evidenza ne è un sottoinsieme. Non esiste un
percorso che possa farla fallire.

Il guadagno è reale ma **dipende dal carico**: *[misurato]* 35 % del runtime a
2 000 pazienti e ~49 % a 4 000 su una variabile di laboratorio con payload
`from_channel(mean(NUMRES))`; 1,2 % / 1,7 % / 3,0 % a 1k/2k/4k su una variabile
di appartenenza a codici.

**1.6 — Cancellazioni**

`native_grain`, `produces`, `act_channel`, `derivation`.

Due note oneste:

- `act_channel()` è **esportata**. Non ha chiamanti, quindi il rischio pratico è
  zero, ma è una rimozione di API — categoria diversa dai due campi invisibili.
- `derivation` raggiunge `audit$internal` *[verificato:
  `.build_channel_intermediates()`, `R/run_variable.R:1542-1545`]*, quindi è una
  rimozione di superficie privata, non un no-op. Si cancella comunque **adesso**
  perché la Fase 4 cancella `audit$internal` per intero: tenerla significa
  trasportare 36 righe morte attraverso tutta la riscrittura per poi cancellarle
  lo stesso.
- **Serve anche un edit in `man/`.** `man/channels.Rd` porta `native_grain` in
  cinque firme `\usage` più un `\item`, e `act_channel` come `\alias` più una riga
  di `\usage`. `R CMD check` lo verifica: il log archiviato in
  `outputs/extractionengine-validation/extractionengine.Rcheck/00check.log` mostra
  *"checking for code/documentation mismatches … OK"*, cioè oggi passa e
  smetterebbe di passare.

**1.7 — De-esportare le quattro funzioni non eseguibili**

`source_spec`, `source_roles`, `validate_source_view`, `edsan_source_specs` —
quattro export su 26 *[verificato: `NAMESPACE` ha 26 `export()` più 8
`S3method()`]* — mentre `.run_selected_channel()` accetta solo `EE_SOURCES`
*[verificato: `R/run_variable.R:674-679`]*. Un autore può costruire una source
spec con successo e poi sentirsi dire "requires a registered prepared EDSAN
source".

Quattro righe di NAMESPACE **più `man/source_spec.Rd`**, che documenta tutti e
quattro insieme: de-esportarli senza toccare quella pagina trasforma un check OK
in un warning di documentazione. È un file solo, non quattro.

**1.8 — Chiavare la cache delle sorgenti preparate sulla coorte**

`.prepare_execution_sources()` esce subito su `isTRUE(attr(sources,
"ee_prepared"))` senza controllare per quale coorte il bundle era stato
preparato — e la preparazione è proprio ciò che applica la restrizione PATID
*[verificato: `R/data.R:155`, `:165-175`]*. Oggi è corretto solo perché
`run_protocol()` riusa la stessa coorte: corretto per coincidenza, non per
costruzione. Tre righe, e la Fase 5 aggiungerebbe una seconda cache allo stesso
schema.

**1.9 — Correggere la motivazione ELTID (terza volta)**

La motivazione semantica è giusta ma da sola è falsificabile: *[riprodotto]* due
alias con spazi di chiave disgiunti, `a | b` qualifica **tutto**, non niente.

La forma durevole ha due clausole, e la seconda è quella che giustifica davvero
il divieto:

> Un combine cross-source su `by = "ELTID"` è rifiutato perché `by` nomina la
> chiave su cui l'espressione è valutata come un unico predicato, e due sorgenti
> non possono posare un segnale sullo stesso elemento. Congiunzione e negazione
> sono quindi degeneri, e la disgiunzione — l'unico operatore che calcola ancora
> qualcosa — calcola esattamente ciò che la stessa espressione calcola a `EVTID`
> o `PATID`. Il grain di elemento qui non compra nulla e induce solo in errore su
> cosa è stato confrontato.

**Sette siti**, non tre:

1. `R/spec.R:445-452` — il commento
2. `R/spec.R:466-471` — il messaggio d'errore
3. `README.md:144-146`
4. `DESIGN.md:128-133`
5. `tests/testthat/test-current-contracts.R:362-364` — il commento
6. `tests/testthat/test-current-contracts.R:376` — **l'asserzione**
   `expect_error(..., "never repeat across sources")`, che pinna la frase falsa.
   Si annuncia da sola (la suite diventa rossa) ma va contata.
7. `man/operators.Rd:29-33` — **scritto a mano**

**`man/operators.Rd` non si rigenera.** *[verificato]* `grep -c "^#'" R/*.R`
restituisce **0 su tutti e undici i file**, e non c'è `RoxygenNote` in
`DESCRIPTION`: tutte e sei le pagine in `man/` sono `.Rd` scritti a mano. Quella
riga è il testo che l'utente vede da `?combine_channels`. Il punto 1.9 esiste
perché questa motivazione è stata sbagliata in tre generazioni di documenti;
spedirne una quarta nella pagina di manuale sarebbe un brutto modo di chiudere.

**1.10 — Risolvere tutte le spec prima di preparare le sorgenti**

Oggi `run_protocol()` controlla classe e nomi delle variabili, prepara l'intera
coorte e solo dentro ciascun `run_variable()` chiama `resolve_variable_spec()`.
Un refuso nella seconda variabile può quindi emergere dopo una normalizzazione
costosa delle sorgenti.

Prima di `.prepare_execution_sources()`, eseguire un preflight fail-fast di tutte
le spec con `resolve_variable_spec()`. La soluzione minima può risolverle una
seconda volta dentro `run_variable()`: il costo è trascurabile rispetto alla
preparazione delle sorgenti e non richiede una nuova astrazione o un nuovo
contratto interno. La deduplicazione si considera solo se una misura la giustifica.

---

### Fase 2 — la dichiarazione mancante

**La decisione: `search_within` diventa obbligatorio per ogni canale
strutturato.** Non "obbligatorio se c'è una finestra". Obbligatorio e basta, come
già lo è per i canali di testo. Se manca, è un errore al build. I valori ammessi
sono `PATID` e `EVTID`.

Il lavoro comincia con una **cancellazione**: si tolgono le righe che oggi
*vietano* `search_within` sui canali strutturati
*[verificato: `R/spec.R:416-420`, senza nessun commento che spieghi perché]*.
`search_within` è già instradato attraverso validazione, risoluzione, entrambi i
printer e il manifest, e `.channel_scope_keys()` lo onora già correttamente.
Toglierlo è davvero una cancellazione, non una feature nuova.

**Perché "e basta" e non "se c'è una finestra".**

Oggi il motore deduce il confine di ricerca da questa riga:

```r
if (is.null(channel_def$window)) grain_keys else "PATID"   # R/run_variable.R:658
#  ^--- ramo 1: "niente finestra ⇒ cerca al grain di output"   → difetto A1
#                                  ^--- ramo 2: "c'è una finestra ⇒ cerca a PATID" → difetto A2
```

Sono **due** deduzioni. Legare l'obbligo alla finestra ne toglierebbe una sola,
la seconda, lasciando la prima intatta — e la prima è quella che produce A1, cioè
il valore che cambia a seconda di chi altro c'è nella coorte, **su variabili che
non dichiarano nessuna finestra**. Quel difetto sopravviverebbe a tutto il piano.

Obbligatorio ovunque invece:

- toglie **entrambe** le deduzioni: `.channel_scope_keys()` diventa una semplice
  lookup;
- rende la regola dei canali strutturati **identica** a quella dei canali di
  testo, che è l'argomento che questa fase usa già per sé stessa;
- fa sì che la Fase 4 non debba mai chiedersi se lo scope di un canale è stato
  dichiarato o indovinato — condizione perché *"la restrizione per task del roster
  è la dichiarazione di scope della Fase 2"* sia vera per **ogni** canale;
- è una sottrazione **più grande**, che è la direzione in cui questa fase già va.

`ELTID` non entra in questo vocabolario. Il caso K/Na sullo stesso prelievo è già
espresso da `combine_channels("k & na", by = "ELTID")` fra alias della stessa
sorgente, mentre `search_within` resta `PATID` o `EVTID`. Sono due decisioni
diverse: la prima sceglie la chiave del combine, la seconda il confine entro cui
il canale può cercare. Si riapre `search_within = "ELTID"` soltanto quando esiste
un consumatore reale con scope a livello di elemento; oggi aggiungerebbe un ramo,
una guardia e test per un caso senza chiamante.

**Costo:** ogni variabile strutturata esistente va ri-autorata con una
dichiarazione in più. È rumore di authoring reale, ed è il prezzo per non avere un
confine che nessuno ha scritto.

**Nella stessa migrazione: `ptype` obbligatorio su `from_channel()`.**

*[misurato]* un batch tutto vuoto pubblica oggi una colonna logical, uno popolato
una double. Un argomento `ptype` e un cast rendono stabile il tipo, ma renderlo
obbligatorio rompe ogni chiamata esistente a `from_channel()`. Non è quindi una
correzione "senza cambio di contratto" della Fase 1.

Si introduce qui, insieme a `search_within`, così ogni variabile viene ri-autorata
una volta sola. `ptype` resta obbligatorio, non opzionale: l'opzione risolverebbe
la divergenza soltanto per chi la dichiara.

**Documentazione nella stessa migrazione:** aggiornare `man/variable_spec.Rd`
per rendere `search_within` obbligatorio anche sui canali strutturati,
`man/operators.Rd` per la nuova firma e l'argomento `ptype`, e le descrizioni ed
esempi corrispondenti in `README.md` e `DESIGN.md`. Le pagine `man/` sono scritte
a mano e non verranno rigenerate automaticamente.

**Perché prima della Fase 4:** il roster non è ben definito senza la
dichiarazione di scope (vedi Fase 4, punto 2).

**Una strada scartata: far intersecare finestra e confine.**

Una versione precedente di questo piano diceva che finestra e confine dovevano
intersecarsi. *[misurato]* quella regola **fa regredire tutte le variabili
"storia di X"**:

> P1 ha la degenza E1 (gen 2024, porta `N185`) e la degenza E2 (gen 2026, indice).
> Variabile: `anchor = index_event(pmsi_actes, ccam("ZZQX001"))`,
> `window = c(-1095, 0)`, `output = bin_output(group_by = "EVTID")` — *"storia di
> IRC dialisi-dipendente nei tre anni prima del ricovero indice"*.
>
> Oggi: E2 → valore 1, copertura `complete`.
> Con l'intersezione e il confine che ricade sul grain di output: **0**, perché la
> riga `N185` sta in E1.

Una retrospettiva di tre anni che può guardare solo dentro il ricovero indice non
è una retrospettiva. La finestra è un filtro sulle **date**; `search_within` è il
**confine**. Si compongono, ma il confine non può avere come default il grain di
output.

---

### Fase 3 — eliminare `channel_coverage` strutturato

La diagnosi corretta del difetto C è a valle degli esecutori. *[verificato]* lo
stesso stato `no_candidate` viene trasformato in due etichette pubbliche diverse:

- `.single_membership_variable()` passa da `.no_candidate_status()` e pubblica
  `complete`;
- `.single_from_channel_variable()` passa da
  `.status_from_processing_state()`, ottiene `unavailable` e pubblica `partial`.

La soluzione non è scegliere una delle due etichette. È eliminare la traduzione.

Per gli esecutori strutturati fail-fast:

- una run restituita ha eseguito il calcolo e pubblica il risultato;
- un errore deterministico interrompe `run_variable()` e non diventa una riga
  `error`;
- zero candidati resta un fatto osservabile — zero righe o conteggio zero — non
  uno stato pubblico `no_candidate`;
- `complete` e `partial` spariscono da `values$channel_coverage`.

`channel_status$selection_status` **deve restare per tutta la Fase 3**. È una
vista operativa pubblica e documentata; `audit$counts` contiene già conteggi
correlati, ma questo non autorizza a togliere una colonna pubblica nel vuoto fra
due fasi. Non è il nuovo nucleo semantico: la Fase 4 può pubblicare
`unavailable`, `no_match` e `matched` come vista della nuova relazione, oppure
eliminarli, ma soltanto nello stesso cambiamento che rende disponibile il loro
sostituto esplicito.

`.no_candidate_status()` non può essere cancellata alla cieca perché serve anche
al percorso `lucene_llm`, che questa fase non riscrive. Va separato l'uso LLM da
quello strutturato; retry ed errori del modello restano fatti di
`processing_status`/attempts, non copertura epistemica.

**Da fare anche qui:** eliminare i due rami di default che fabbricano stati
(difetto K). `.reduce_channel_result()` fa diventare `no_eligible_source` un task
assente per default (`R/channel-combine.R:71`) e `.channel_status_from_state()`
ha un catch-all `unavailable` (`:50`). Un task o uno stato inatteso deve fallire,
non essere convertito nello stato apparentemente più prudente.

**Quello che questa fase NON fa:** consolidare i tre esecutori sotto il contratto
attuale a sei frame. Sarebbe lavoro fatto due volte, perché la Fase 4 sostituisce
proprio quel contratto. La consolidazione è la prima fetta verticale della Fase 4.

---

### Fase 3b — provider e modello fuori dal pacchetto

Spostato **prima** del lavoro LLM della Fase 4, non in fondo. Se la Fase 4
prototipa l'esecuzione pigra del modello usando l'interfaccia attuale, la Fase 5
cambierebbe quell'interfaccia subito dopo.

`use_channel(chat = ellmer::chat_openai(...))`, oppure
`provider = ellmer::chat_ollama, model = "gemma3:4b"`. L'approvazione dei modelli
diventa un argomento di run, o sparisce — il modello è già registrato in
`llm_calls`.

---

### Fase 4 — il nucleo relazionale

Al posto delle sei tabelle che ogni esecutore produce oggi, **una sola tabella
lunga** che non copia le righe delle sorgenti ma le **indica** — task, alias,
chiavi identificative, il riferimento alla riga sorgente, e in che stadio quella
riga è arrivata (vista, filtrata dalla finestra, selezionata, usata, citata).
Evidenza, conteggi e viste operative smettono di essere costruiti a mano e
diventano interrogazioni su quella tabella.

Assorbe: il roster vero, il runtime quadratico, la memoria ~9×, e l'esecuzione
pigra del payload (che richiede di limitare l'esecuzione a livello di singola
chiave, cosa che l'interfaccia attuale degli esecutori non permette).

**Quattro cose da fare bene:**

**1. L'universo si calcola in due modi diversi a seconda del livello.**

Non esiste "un universo" solo. La regola:

> Per un dato task, a un dato livello di chiave:
> - se il livello è **al grain di output o più grosso** → l'universo è la chiave
>   del task stesso;
> - se il livello è **più fine** → l'universo è il roster, **intersecato** con lo
>   scope di ricerca di quel task.

A grain uguale l'universo corretto sono i task, e basta. Sostituirci un roster a
livello di run darebbe a una variabile `index_event` un universo fatto di ogni
degenza presente nelle sorgenti, cambiando risposte che oggi sono corrette.

**2. Il roster va intersecato con lo scope di ricerca di ogni canale
referenziato**, o la negazione a grain fine sovra-qualifica. Un task con
`window = c(-30, 30)` non ha mai guardato degenze di cinque anni prima; se
entrano nell'universo senza restrizione sono tutte FALSE, quindi `!a & !b` le
qualifica e il valore si ribalta a 1.

Il roster conserva anche la sorgente di appartenenza. A `ELTID`, dove i domini
delle sorgenti sono disgiunti, l'universo viene ristretto alla sorgente comune dei
canali partecipanti: un `ELTID` biologico non entra nel complemento di due canali
documentali. Questo è coerente con il divieto di combine cross-source a `ELTID`.

**Conseguenza importante: la restrizione per task del roster *è* la dichiarazione
di scope della Fase 2.** Se si implementano come due cose diverse divergeranno
esattamente come sono divergite le mappature a valle degli stati. **La
Fase 4 consuma il resolver della Fase 2, non ne cresce uno proprio.**

Quando i canali referenziati hanno scope diversi, l'universo valutabile è
l'intersezione dei loro scope. Non è un'affermazione epistemica — "quali unità ha
guardato il motore per ogni canale referenziato" è esattamente la domanda
operativa che la decisione 2 consente.

**3. Il valore di una variabile può dipendere da quali sorgenti sono state passate
alla run.** A `PATID` e `EVTID`, aggiungere `biology` può ampliare il roster usato
da una variabile che legge `pmsi_diag`. A `ELTID`, invece, una sorgente estranea
non entra nell'universo. **La provenienza del roster** — sorgente e numero di
unità per livello — deve stare nel manifest, o il risultato non è riproducibile.

Trappola implementativa: `.prepare_execution_sources()` salta ciò che non è un
data frame *[verificato: `R/data.R:165`]*, quindi una sorgente documentale
tCorpus **non è mai ristretta alla coorte**. Il braccio documentale del roster va
costruito da `.document_index()` o il roster conterrà degenze fuori coorte.

**4. Quella tabella non basta per il percorso testo/LLM.**

La forma descritta sopra basta per le occorrenze strutturate, dove ogni cosa è
una riga di sorgente. Non basta per quello che viene mandato al modello: un
documento genera **più snippet**, gli snippet hanno un ID e un ordine che valgono
solo dentro quel task, e il testo del prompt, la chiamata al modello e la
citazione non stanno tutti allo stesso livello della riga sorgente.

Serve aggiungere il tipo e l'ID dell'artefatto più una posizione opzionale, oppure
tenere una tabella separata per gli item di prompt. Da decidere costruendo, non
prima.

**La fetta verticale deve includere testo/LLM, non solo il percorso di laboratorio
più facile.** Ed è lì che la consolidazione degli esecutori (ex Fase 3) trova
posto.

**Nota sulla motivazione:** la versione precedente del piano diceva che il roster
richiede di cambiare il contratto di ritorno dell'esecutore di testo, e usava
questo per giustificare la guardia provvisoria. **Non è più vero.** Quello valeva
per la definizione di roster del round 1 (righe pre-selettore dai canali
partecipanti). La **decisione 4** l'ha superata: un roster costruito "dalle
sorgenti passate alla run" viene dai frame preparati, prima che qualunque
esecutore giri, e non tocca nessun contratto di esecutore. *[verificato]* tutte e
quattro le sorgenti registrate portano PATID/EVTID/ELTID, e `.document_index()`
trasforma già un tCorpus in quel frame.

La guardia della Fase 1.2 resta comunque giustificata — è tre righe e converte
risposte sbagliate in errori — ma **non per quella ragione**.

---

### Fase 5 — il resto

- Riuso dei canali fra variabili, **ristretto al recupero Lucene e alle chiamate
  al modello**. Il profilo dice che l'esecutore strutturato è il 2,1 % di un run
  di appartenenza: cachearlo compra ~2 % e aggiunge una superficie di correttezza
  sulla chiave di cache che dovrebbe includere il selettore risolto, le chiavi di
  scope, la finestra e ogni semplice parametro esterno esplicitamente supportato.
  Se una dipendenza non è identificabile — per esempio una closure arbitraria —
  quel lavoro non è cacheabile. La metà deterministica si taglia.
- Identità dello snapshot delle sorgenti e versioni di pacchetto/runtime nel
  manifest. Devono precedere qualunque cache fra variabili.
- Il manifest **non** serializza l'ambiente R. Registra però i semplici valori
  atomici letti esplicitamente con `.env$nome`: vengono fotografati una volta
  prima dell'esecuzione e la stessa fotografia alimenta calcolo e manifest.
  Funzioni locali, closure, active binding e oggetti arbitrari restano codice di
  authoring versionato, non payload del manifest.
- `execution_manifest` come `list(spec = resolved_spec, ...)` invece di una copia
  a mano di 74 righe: ~130 righe cancellate, e aggiungere un argomento a
  `use_channel()` passa da cinque siti coordinati a uno. *[verificato: i cinque
  siti ci sono ancora]*

---

## Parte 4 — Rifiuti espliciti

Registrati come decisioni, non lasciati cadere. Entrambi i revisori hanno
insistito che un rilievo "assorbito per omissione" è peggio di uno rifiutato.

| Rilievo | Decisione | Ragione |
|---|---|---|
| `from_channel()` su più alias (rapporto sodio/potassio, media delle medie) | **Rifiutato per ora** | È un confine di prodotto, non un difetto. Determina se "rapporto Na/K" è una variabile audited o due variabili più uno script. Si riapre quando esiste un secondo caso reale di riconciliazione. |
| Cache deterministica fra variabili | **Rifiutato** | ~2 % di guadagno, superficie di correttezza sproporzionata. Vedi Fase 5. |
| `dbplyr` / pushdown SQL | **Rifiutato per ora** | Le quosure R arbitrarie, il recupero corpustools e i passi LLM non sono automaticamente traducibili. Si riapre quando esiste un chiamante con una tabella lazy vera. |
| Tabella di studio in formato lungo da `run_protocol()` | **Rifiutato** | La forma larga (una riga per unità, una colonna per variabile) resta compatibile con tutto il piano; quella lunga no, perché una sola colonna `value` non può tenere double e character insieme. Vale a prescindere da `ptype`; il `ptype` obbligatorio della Fase 2 la preclude anche formalmente. |
| `values` come schema unico + registro dei 60 nomi riservati | **Da decidere in Fase 4** | È il posto naturale: pubblicare il record LLM annidato fa sparire il registro e tre controlli di collisione (~90 righe). Va deciso lì, esplicitamente. |
| `on_incomplete = "error"` (far fallire la run quando una fonte manca) | **Rifiutato** | Decisione del proprietario. GPT sosteneva che è una policy di governance separata dall'algebra, non una seconda logica — argomento valido, ma non c'è oggi un caso in cui serva. Si riapre se qualcuno chiede di bloccare un protocollo su copertura incompleta. |
| Serializzare funzioni, closure o l'intero ambiente R nel manifest | **Rifiutato** | Il manifest non è una capsula di replay della sessione. Il rifiuto non comprende i semplici parametri `.env` espliciti che cambiano il calcolo: la Fase 5 li registra. |

---

## Parte 5 — Numeri onesti

- **"La Fase 1 raddoppia la velocità" è specifico del carico.** Vale per le
  variabili con payload denso di evidenza. Per una variabile di appartenenza a
  codici — la forma di cui è fatto un protocollo — la cancellazione
  dell'asserzione (punto 1.5) vale ~2 %. È il punto **1.1** che sposta il 61-68 %,
  a seconda del profilo; sul caso `from_channel` provato, il prototipo di 1.1 è
  circa 17× più veloce. Sono misure dei singoli assemblatori, non promesse sul
  tempo end-to-end.
- **La complessità dopo la Fase 1 va rimisurata, non predetta.** Oggi
  `.single_from_channel_variable()` cresce 1,23 → 2,46 → 5,29 → 9,34 secondi a
  500/1k/2k/4k task; il prototipo cresce 0,07 → 0,14 → 0,30 → 0,55. La Fase 4
  resta necessaria per il contratto e la memoria trattenuta, non per attribuirsi
  in anticipo un guadagno che 1.1 potrebbe già comprare.
- **La memoria è il vincolo vero, non la velocità.** 25,5 MB restituiti per
  variabile su 2,8 MB di sorgente; ~250 MB per variabile a 20 000 pazienti; ~10 GB
  per un protocollo da 40 variabili. Non è una raffinatezza prestazionale: è ciò
  che fa **fallire** `run_protocol()` invece di renderlo lento.
- **`act_channel()` non è una cancellazione a rischio zero.** È zero in pratica
  (nessun chiamante) ma è una rimozione di API.

---

## Ordine di esecuzione

```
Fase 0   comparatore prima/dopo su fixture sintetiche; normalizzazione fail-fast
Fase 1   1.1 vettorizzare  →  1.2 guardia  →  1.3 data mask  →  1.4 dichiarare
         il limite del manifest  →  1.5-1.10 sottrazioni e correzioni
Fase 2   search_within OBBLIGATORIO per OGNI canale, con PATID/EVTID;
         ptype obbligatorio nella stessa migrazione di authoring
Fase 3   eliminare channel_coverage strutturato e i due rami di default;
         errori deterministici restano fail-fast; selection_status sopravvive
         fino al suo eventuale sostituto in Fase 4
Fase 3b  provider/modello fuori dal pacchetto
Fase 4   fetta verticale (strutturato + testo/LLM) → una tabella lunga al posto
         di sei, roster source-qualified, universo in due modi, payload pigro
Fase 5   riuso Lucene/LLM, identità nel manifest, semplici parametri .env,
         manifest come resolved_spec
```

Dentro la Fase 1, **1.1, 1.5, 1.6, 1.7 e 1.8 sono indipendenti** fra loro e da
tutto il resto: si possono fare in qualsiasi ordine. Il punto 1.10 deve precedere
la prima preparazione costosa delle sorgenti; 1.4 è una dichiarazione di confine,
non plumbing da coordinare con 1.3.
