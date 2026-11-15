# Denutrition (HAS grid) as a protocol sheet

Status: first draft, never run. It transcribes the rules of the archived
fact-layer prototype (`grid.R` and `facts.R` at tag
`archive/fact-layer-prototype-2026-10-04`). I could not read `redsan-coding`
itself, so the prototype is my only source. I invented no threshold.

Every line that goes beyond the first sketch carries a tag such as `# +3`. The
numbers point to the list in `README.md`.

## The sheet

```yaml
protocol:
  name: Denutrition, HAS grid
  question: >
    Does the record support a diagnosis of denutrition for this stay,
    and at which severity?
  target_code: [E43, E44.0]
  never_read: E40 to E46          # the codes under audit are not evidence
  reference: HAS 2019 (adults, children), HAS 2021 (70 and over)

population:
  unit: stay
  include: the audit sample
  strata:                                                    # +4
    child: age < 18
    adult: 18 <= age < 70
    age70: age >= 70

facts:
  # ---- structured sources ----
  albumin:
    type: lab
    label: albumin                                           # +12
    label_excludes: [prealb, micro, urin, LCR, quotient, volume, glyc, ratio, ascite, pleural]
    unit: g/L
    plausible: [5, 60]

  coded_condition:
    type: code
    system: CIM-10
    categories:
      sepsis: [A40, A41, R57.2, R65.1]
      diabetic_crisis: [E10 to E14 with 4th character 0 or 1]
      deep_infection: [I33, M86, M46.2 to M46.5, M00, T84.5]
      malignancy: [C00 to C97]
      dialysis: [Z99.2, Z49]
      chronic_kidney_disease: [N18.4, N18.5]
      cirrhosis: [K70.3, K71.7, K74.4 to K74.6]
      chronic_infection: [A15 to A19]
    recorded_only:                                           # +11
      heart_failure: [I50]        # no stage in the code
      chronic_respiratory_failure: [J96.1]
      stroke: [I61, I63, I64]
      acute_pancreatitis: [K85]   # no severity in the code

  major_surgery_act:
    type: code
    system: CCAM
    label: >                                                 # +12
      colectomie, gastrectomie, hepatectomie, pancreatectomie, oesophagectomie,
      proctectomie, resection digestive, pontage coronaire, lobectomie,
      pneumonectomie, transplantation

  # ---- numbers copied from documents ----
  weight:
    type: number_in_text
    unit: kg
    attributes:                                              # +10
      role: [current, usual, before_disease, earlier]
      when: words copied from the record

  height:
    type: number_in_text
    unit: cm or m

  bmi:
    type: number_in_text
    unit: kg/m2
    also_computed: weight[current] / height^2                # +9

  weight_loss:
    type: number_in_text
    unit: "% or kg"
    attributes:                                              # +10
      against: [period, usual, before_disease]
      period: words copied from the record, read as days     # +5
    negated_by: weight stated as stable, or no weight loss
    also_computed:                                           # +9
      - from two weights the record compares                 # +6
      - from a loss in kg and the highest known weight, as a lower bound   # +3

  intake:
    type: mention
    find: model
    attributes:                                              # +10
      status: [reduced, preserved]
      reduction_percent: number, from the amount written
      duration: words copied from the record, read as days
      basis: [habitual, needs, unspecified]

  artificial_feeding:
    type: mention
    find: model
    attributes:
      route: [tube, enteral, parenteral]
      for_oral_failure: [yes, no]

  absorption_cause:
    type: mention
    find: model
    categories: [exocrine_pancreatic_insufficiency, inflammatory_bowel_disease,
                 intestinal_resection_or_bypass, short_bowel, coeliac_disease,
                 cholestasis, diarrhoea, steatorrhoea, other]

  muscle_measure:
    type: number_in_text
    attributes:
      method: [grip_strength, gait_speed, ct_l3, bia_smi, bia_ffmi, dexa_asmi, other]
      called_reduced: words copied from the record

  # ---- conditions named in documents ----
  condition:
    type: mention
    find: model
    attributes:                                              # +10
      status: [active, stable, history, suspected, excluded, family]
      onset: [before_admission, at_admission, during_stay, unknown]
      when: words copied from the record
      stage: words copied from the record                    # +10
      treatment_duration: words copied from the record
    categories:
      sepsis: sepsis or septic shock
      icu_organ_failure: organ failure managed in intensive care
      major_surgery: abdominal, thoracic, cardiac or major vascular surgery, transplant
      major_trauma_or_burn: polytrauma, severe head injury, extensive burn
      severe_pancreatitis: acute pancreatitis with organ failure over 48 h, or necrosis
      diabetic_crisis: ketoacidosis or hyperosmolar syndrome
      deep_infection: endocarditis, bone and joint infection, spondylodiscitis
      malignancy: invasive cancer, solid or blood
      heart_failure: heart failure
      cardiac_cachexia: cardiac cachexia named as such
      repeated_hf_decompensation: repeated cardiac decompensations
      copd: COPD
      home_oxygen_or_niv: long-term oxygen or non-invasive ventilation
      chronic_kidney_disease: chronic kidney disease
      dialysis: chronic dialysis
      cirrhosis: cirrhosis or chronic liver failure
      chronic_inflammatory_disease: IBD, rheumatoid arthritis, vasculitis, lupus
      chronic_infection: tuberculosis, invasive mycosis, chronic osteitis, HIV
    recorded_only:                                           # +11
      simple_infection: any other acute infection
      stroke: stroke or other acute neurological event
      fracture: any fracture
      fluid_electrolyte_disorder: dehydration, electrolyte disorder, hypoglycaemia
      other_acute_condition: the acute reason for admission, when nothing above fits
      in_situ_or_benign_tumour: in situ, non-invasive or benign tumour
      neurocognitive_disorder: dementia

  antibiotic_course:
    type: computed                                           # +9
    formula: treatment_duration of an infection, in days

  antituberculous_drug:
    type: mention
    find: words
    words: [rifampicine, isoniazide, ethambutol, pyrazinamide, rifater, rifinah,
            rimifon, myambutol, dexambutol]

  dietitian_box:
    type: mention
    find: words
    words: ["(present) Situation d'agression"]
    asserted_by: dietitian
    counts: no                                               # +11

  growth_channel_drop: {type: judgement}                     # +8
  stature_slowing: {type: judgement}                         # +8

criteria:
  measures:                                                  # +2
    bmi: {take: lowest, of: bmi, ignore: history, prefer: computed}
    albumin: {take: lowest, of: albumin}
    loss_1m: {take: largest_change, of: weight_loss, over_days: [28, 31]}      # +5
    loss_6m: {take: largest_change, of: weight_loss, over_days: [180, 184]}    # +5
    loss_usual: {take: largest_change, of: weight_loss, against: [usual, before_disease]}

  thresholds:                                                # +4
    iotf_17: table by age and sex (IOTF curve 17)
    iotf_18_5: table by age and sex (IOTF curve 18.5)
    grip_cut: {M: 26, F: 16}
    ct_l3_cut: {M: 52.4, F: 38.5}
    bia_smi_cut: {M: 7.0, F: 5.7}
    bia_ffmi_cut: {M: 17, F: 15}
    dexa_asmi_cut: {M: 7.23, F: 5.67}

  # ---- group 1: phenotypic, one is enough ----
  phenotypic:
    loss:
      any_of: [loss_1m >= 5, loss_6m >= 10, loss_usual >= 10]
    bmi_low:                                                 # +4
      adult: bmi < 18.5
      age70: bmi < 22
      child: bmi < iotf_18_5
    muscle:
      any_measured:                                          # +1
        - grip_strength < grip_cut
        - gait_speed < 0.8
        - ct_l3 < ct_l3_cut
        - bia_smi < bia_smi_cut
        - bia_ffmi < bia_ffmi_cut
        - dexa_asmi < dexa_asmi_cut
        - present: muscle_measure
          where: [called_reduced]
    growth_channel:
      child: {judged: growth_channel_drop}                   # +8

  # ---- group 2: etiologic, one is enough ----
  etiologic:
    intake:
      any_of:
        - present: artificial_feeding
          where: [for_oral_failure]
        - present: intake
          where: [reduction_percent >= 50, duration_days > 7, "basis: habitual or needs"]
        - present: intake
          where: [status reduced, duration_days > 14, "basis: habitual or needs"]
      refuted_by: intake stated as preserved, and no reduction stated   # +1
    absorption:
      present: absorption_cause
      where: [not history]
    aggression:
      any_of: [aggression_acute, aggression_chronic, aggression_malignant]

  aggression_acute:
    list: &acute [sepsis, icu_organ_failure, major_surgery, major_trauma_or_burn,
                  severe_pancreatitis, diabetic_crisis, deep_infection]
    any_of:
      - present: *acute
        where: ["onset: before_admission or at_admission", "status: active"]
      - present: *acute
        dated_within: {period_of: weight_loss}               # +6
      - present: antibiotic_course
        where: [days >= 21, "onset: before_admission or at_admission", "status: active"]
        assumed: yes
        note: The text says "several weeks". 21 days is a provisional reading.
      - present: antibiotic_course
        where: [days >= 21]
        dated_within: {period_of: weight_loss}               # +6
        assumed: yes

  aggression_chronic:
    any_of:
      - present: heart_failure
        where: ["stage: NYHA III or IV"]                     # +10
      - present: copd
        where: ["stage: GOLD 3 or 4, or severe"]             # +10
      - present: chronic_kidney_disease
        where: ["stage: 4 or 5, or GFR < 30, or code N18.4 or N18.5"]   # +10
      - present: [cardiac_cachexia, repeated_hf_decompensation, home_oxygen_or_niv,
                  dialysis, cirrhosis]
        where: [not history]
      - present: [chronic_inflammatory_disease, chronic_infection]
        where: ["status: active"]
      - present: antituberculous_drug
        where: [not history]
        at_least: 2
        distinct: drug

  aggression_malignant:
    present: malignancy
    where: [not history, "stage: not pTa, pTis, in situ, CIS or Bowen"]   # +10

  # ---- group 3: moderate, read only if the diagnosis holds ----
  moderate:
    bmi:
      adult: 17 < bmi < 18.5
      age70: 20 <= bmi < 22
      child: iotf_17 < bmi < iotf_18_5
    loss:
      adult: &loss_moderate
        any_of: [5 <= loss_1m < 10, 10 <= loss_6m < 15, 10 <= loss_usual < 15]
        lower_bound_cannot_refute_top: yes                   # +3
        assumed: yes
        note: The HAS text does not close this band at its top. Test note 1 does.
      age70: *loss_moderate
      child:
        any_of: [5 <= loss_1m <= 10, 10 < loss_6m <= 15]
        lower_bound_cannot_refute_top: yes
    albumin:
      adult: 30 < albumin < 35
      age70: albumin > 30
    growth_channel:
      child: {judged: growth_channel_drop}                   # +8

  # ---- group 4: severe, read only if the diagnosis holds ----
  severe:
    bmi:
      adult: bmi <= 17
      age70: bmi < 20
      child: bmi <= iotf_17
    loss:
      adult: &loss_severe
        any_of: [loss_1m >= 10, loss_6m >= 15, loss_usual >= 15]
      age70: *loss_severe
      child:
        any_of: [loss_1m > 10, loss_6m > 15]
    albumin:
      adult: albumin <= 30
      age70: albumin <= 30
    growth_channel:
      child: {judged: growth_channel_drop}                   # +8
    stature:
      child: {judged: stature_slowing}                       # +8

answer:
  outputs:
    diagnosis: phenotypic AND etiologic
    severity:                                                # +7
      only_if: diagnosis
      first_of:
        - severe: severe
        - moderate: moderate
        - indeterminate: otherwise
    suggested_code: {severe: E43, moderate: E44.0}
  report:
    - severity_unresolved   # unknown criteria that could still raise the grade   # +7
    - bmi
    - albumin
    - loss_1m
    - loss_6m
    - loss_usual
```

## How it reads

The `criteria` block reads like the HAS grid. A DIM doctor can check
`adult: bmi < 18.5` against the fiche without help. That part works.

The `facts` block is about half of the sheet (150 of 320 lines). It is where the clinical
knowledge sits: the 25 condition categories, the roles of a weight, the
statuses. A DIM doctor can read it. A local model could not have written it
from a plain question. It came out of weeks of your review of real stays.

## Where I had to cheat

These lines look tidy but hide a problem. I list them so the tidiness does not
mislead you.

1. **The `where:` lines in quotes are prose.** `"stage: NYHA III or IV"` is a
   sentence, not something a validator can check. The prototype does this with
   regular expressions on the copied words. See point 10 in `README.md`.
2. **`refuted_by` is a sentence too.** The real rule is: not met when every
   intake fact is a denial.
3. **`dated_within: {period_of: weight_loss}` hides arithmetic.** It compares
   how long ago the condition began with how long the weight loss covers.
4. **`&acute` and `*acute` are YAML shorthand** for "define this list once,
   reuse it". It is valid YAML and it is ugly. A real format needs a cleaner
   way to name a list.
5. **The category word lists are missing.** The engine's grounding rule needs,
   for each category, the words that must appear in the quote ("sepsis",
   "choc septique"). I left them out. With them the sheet is about 80 lines
   longer.
6. **The prompt is missing.** The model is told far more than the one-line
   meanings above: copy numbers as written, never compute, how to choose a
   status. Either the sheet carries that text, or the engine writes it from the
   sheet. The second is harder than it looks.
7. **The sheet is in English.** The prompt and the DIM readers are French. A
   real sheet would be in French.
