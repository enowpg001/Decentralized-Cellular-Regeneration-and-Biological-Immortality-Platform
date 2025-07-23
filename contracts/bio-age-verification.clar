;; Biological Age Reversal Verification Contract
;; Monitors and validates successful age reversal interventions

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-PATIENT-NOT-FOUND (err u401))
(define-constant ERR-ASSESSMENT-NOT-FOUND (err u402))
(define-constant ERR-INVALID-INPUT (err u403))
(define-constant ERR-INSUFFICIENT-DATA (err u404))
(define-constant ERR-VERIFICATION-FAILED (err u405))

;; Data Variables
(define-data-var next-patient-id uint u1)
(define-data-var next-assessment-id uint u1)
(define-data-var next-verification-id uint u1)

;; Data Maps
(define-map patients
  { patient-id: uint }
  {
    wallet: principal,
    chronological-age: uint,
    baseline-biological-age: uint,
    current-biological-age: uint,
    assessment-count: uint,
    last-assessment-block: uint,
    verified-reversals: uint,
    active: bool
  }
)

(define-map biological-assessments
  { assessment-id: uint }
  {
    patient-id: uint,
    assessor: principal,
    assessment-block: uint,
    telomere-length: uint,
    dna-methylation-age: uint,
    protein-markers: (list 10 uint),
    metabolic-markers: (list 5 uint),
    cognitive-score: uint,
    physical-fitness-score: uint,
    calculated-bio-age: uint,
    confidence-level: uint
  }
)

(define-map age-verifications
  { verification-id: uint }
  {
    patient-id: uint,
    verifier: principal,
    verification-block: uint,
    previous-bio-age: uint,
    current-bio-age: uint,
    reversal-amount: uint,
    verification-method: (string-ascii 50),
    supporting-data: (string-ascii 200),
    verified: bool,
    verification-score: uint
  }
)

(define-map authorized-assessors
  { assessor: principal }
  {
    active: bool,
    specialization: (string-ascii 50),
    accuracy-score: uint,
    total-assessments: uint,
    certification-level: uint
  }
)

(define-map biomarker-weights
  { biomarker-type: (string-ascii 30) }
  {
    weight: uint,
    reliability-score: uint,
    age-correlation: uint
  }
)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-authorized-assessor (assessor principal))
  (default-to false (get active (map-get? authorized-assessors { assessor: assessor })))
)

;; Patient Management Functions
(define-public (register-patient (chronological-age uint) (baseline-biological-age uint))
  (let
    (
      (patient-id (var-get next-patient-id))
    )
    (asserts! (> chronological-age u0) ERR-INVALID-INPUT)
    (asserts! (> baseline-biological-age u0) ERR-INVALID-INPUT)
    (asserts! (<= baseline-biological-age u150) ERR-INVALID-INPUT)

    (map-set patients
      { patient-id: patient-id }
      {
        wallet: tx-sender,
        chronological-age: chronological-age,
        baseline-biological-age: baseline-biological-age,
        current-biological-age: baseline-biological-age,
        assessment-count: u0,
        last-assessment-block: block-height,
        verified-reversals: u0,
        active: true
      }
    )

    (var-set next-patient-id (+ patient-id u1))
    (ok patient-id)
  )
)

;; Assessment Functions
(define-public (create-biological-assessment
  (patient-id uint)
  (telomere-length uint)
  (dna-methylation-age uint)
  (protein-markers (list 10 uint))
  (metabolic-markers (list 5 uint))
  (cognitive-score uint)
  (physical-fitness-score uint))
  (let
    (
      (assessment-id (var-get next-assessment-id))
      (patient (unwrap! (map-get? patients { patient-id: patient-id }) ERR-PATIENT-NOT-FOUND))
      (calculated-age (calculate-biological-age telomere-length dna-methylation-age protein-markers metabolic-markers cognitive-score physical-fitness-score))
      (confidence (calculate-assessment-confidence protein-markers metabolic-markers))
    )
    (asserts! (is-authorized-assessor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> telomere-length u0) ERR-INVALID-INPUT)
    (asserts! (> dna-methylation-age u0) ERR-INVALID-INPUT)
    (asserts! (<= cognitive-score u100) ERR-INVALID-INPUT)
    (asserts! (<= physical-fitness-score u100) ERR-INVALID-INPUT)

    (map-set biological-assessments
      { assessment-id: assessment-id }
      {
        patient-id: patient-id,
        assessor: tx-sender,
        assessment-block: block-height,
        telomere-length: telomere-length,
        dna-methylation-age: dna-methylation-age,
        protein-markers: protein-markers,
        metabolic-markers: metabolic-markers,
        cognitive-score: cognitive-score,
        physical-fitness-score: physical-fitness-score,
        calculated-bio-age: calculated-age,
        confidence-level: confidence
      }
    )

    ;; Update patient's current biological age if confidence is sufficient
    (if (>= confidence u75)
      (map-set patients
        { patient-id: patient-id }
        (merge patient {
          current-biological-age: calculated-age,
          assessment-count: (+ (get assessment-count patient) u1),
          last-assessment-block: block-height
        })
      )
      true
    )

    (var-set next-assessment-id (+ assessment-id u1))
    (ok assessment-id)
  )
)

(define-private (calculate-biological-age
  (telomere-length uint)
  (dna-methylation-age uint)
  (protein-markers (list 10 uint))
  (metabolic-markers (list 5 uint))
  (cognitive-score uint)
  (physical-fitness-score uint))
  (let
    (
      (telomere-weight u25)
      (methylation-weight u30)
      (protein-weight u20)
      (metabolic-weight u15)
      (cognitive-weight u5)
      (fitness-weight u5)
      (telomere-age (/ (* telomere-length u100) u8000)) ;; Simplified calculation
      (protein-avg (/ (fold + protein-markers u0) u10))
      (metabolic-avg (/ (fold + metabolic-markers u0) u5))
      (weighted-sum (+
        (/ (* telomere-age telomere-weight) u100)
        (/ (* dna-methylation-age methylation-weight) u100)
        (/ (* protein-avg protein-weight) u100)
        (/ (* metabolic-avg metabolic-weight) u100)
        (/ (* (- u100 cognitive-score) cognitive-weight) u100)
        (/ (* (- u100 physical-fitness-score) fitness-weight) u100)
      ))
    )
    weighted-sum
  )
)

(define-private (calculate-assessment-confidence (protein-markers (list 10 uint)) (metabolic-markers (list 5 uint)))
  (let
    (
      (protein-count (len protein-markers))
      (metabolic-count (len metabolic-markers))
      (base-confidence u50)
      (protein-bonus (* protein-count u3))
      (metabolic-bonus (* metabolic-count u4))
    )
    (if (<= (+ base-confidence protein-bonus metabolic-bonus) u100)
      (+ base-confidence protein-bonus metabolic-bonus)
      u100
    )
  )
)

;; Verification Functions
(define-public (create-age-verification (patient-id uint) (verification-method (string-ascii 50)) (supporting-data (string-ascii 200)))
  (let
    (
      (verification-id (var-get next-verification-id))
      (patient (unwrap! (map-get? patients { patient-id: patient-id }) ERR-PATIENT-NOT-FOUND))
      (previous-age (get baseline-biological-age patient))
      (current-age (get current-biological-age patient))
      (reversal-amount (if (< current-age previous-age) (- previous-age current-age) u0))
    )
    (asserts! (is-authorized-assessor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (get assessment-count patient) u1) ERR-INSUFFICIENT-DATA)
    (asserts! (> reversal-amount u0) ERR-VERIFICATION-FAILED)

    (map-set age-verifications
      { verification-id: verification-id }
      {
        patient-id: patient-id,
        verifier: tx-sender,
        verification-block: block-height,
        previous-bio-age: previous-age,
        current-bio-age: current-age,
        reversal-amount: reversal-amount,
        verification-method: verification-method,
        supporting-data: supporting-data,
        verified: true,
        verification-score: (calculate-verification-score reversal-amount verification-method)
      }
    )

    ;; Update patient's verified reversals count
    (map-set patients
      { patient-id: patient-id }
      (merge patient {
        verified-reversals: (+ (get verified-reversals patient) u1)
      })
    )

    (var-set next-verification-id (+ verification-id u1))
    (ok verification-id)
  )
)

(define-private (calculate-verification-score (reversal-amount uint) (method (string-ascii 50)))
  (let
    (
      (base-score (* reversal-amount u10))
      (method-multiplier (if (is-eq method "comprehensive-panel") u2
                          (if (is-eq method "telomere-methylation") u15
                            u1)))
    )
    (if (<= (* base-score method-multiplier) u100)
      (* base-score method-multiplier)
      u100
    )
  )
)

;; Provider Management Functions
(define-public (register-assessor (assessor principal) (specialization (string-ascii 50)) (certification-level uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (<= certification-level u5) ERR-INVALID-INPUT)

    (map-set authorized-assessors
      { assessor: assessor }
      {
        active: true,
        specialization: specialization,
        accuracy-score: u75,
        total-assessments: u0,
        certification-level: certification-level
      }
    )
    (ok true)
  )
)

(define-public (set-biomarker-weight (biomarker-type (string-ascii 30)) (weight uint) (reliability-score uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (<= weight u100) ERR-INVALID-INPUT)
    (asserts! (<= reliability-score u100) ERR-INVALID-INPUT)

    (map-set biomarker-weights
      { biomarker-type: biomarker-type }
      {
        weight: weight,
        reliability-score: reliability-score,
        age-correlation: u80
      }
    )
    (ok true)
  )
)

;; Analysis Functions
(define-public (calculate-reversal-rate (patient-id uint))
  (let
    (
      (patient (unwrap! (map-get? patients { patient-id: patient-id }) ERR-PATIENT-NOT-FOUND))
      (baseline (get baseline-biological-age patient))
      (current (get current-biological-age patient))
      (chronological (get chronological-age patient))
    )
    (if (< current baseline)
      (ok {
        absolute-reversal: (- baseline current),
        percentage-reversal: (/ (* (- baseline current) u100) baseline),
        biological-vs-chronological: (if (< current chronological) (- chronological current) u0)
      })
      (ok {
        absolute-reversal: u0,
        percentage-reversal: u0,
        biological-vs-chronological: u0
      })
    )
  )
)

;; Read-only Functions
(define-read-only (get-patient (patient-id uint))
  (map-get? patients { patient-id: patient-id })
)

(define-read-only (get-assessment (assessment-id uint))
  (map-get? biological-assessments { assessment-id: assessment-id })
)

(define-read-only (get-verification (verification-id uint))
  (map-get? age-verifications { verification-id: verification-id })
)

(define-read-only (get-assessor-info (assessor principal))
  (map-get? authorized-assessors { assessor: assessor })
)

(define-read-only (get-biomarker-weight (biomarker-type (string-ascii 30)))
  (map-get? biomarker-weights { biomarker-type: biomarker-type })
)

(define-read-only (get-contract-stats)
  {
    next-patient-id: (var-get next-patient-id),
    next-assessment-id: (var-get next-assessment-id),
    next-verification-id: (var-get next-verification-id)
  }
)
