;; Regenerative Medicine Access Equity Contract
;; Ensures life extension treatments reach all socioeconomic groups

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-PATIENT-NOT-FOUND (err u501))
(define-constant ERR-INSUFFICIENT-FUNDS (err u502))
(define-constant ERR-INVALID-INPUT (err u503))
(define-constant ERR-SUBSIDY-NOT-FOUND (err u504))
(define-constant ERR-ALREADY-APPLIED (err u505))
(define-constant ERR-ELIGIBILITY-FAILED (err u506))

;; Data Variables
(define-data-var next-patient-id uint u1)
(define-data-var next-subsidy-id uint u1)
(define-data-var total-fund-balance uint u0)
(define-data-var next-application-id uint u1)

;; Data Maps
(define-map patients
  { patient-id: uint }
  {
    wallet: principal,
    income-level: uint,
    geographic-region: (string-ascii 50),
    age: uint,
    medical-need-score: uint,
    subsidies-received: uint,
    total-treatments: uint,
    active: bool
  }
)

(define-map subsidy-programs
  { subsidy-id: uint }
  {
    program-name: (string-ascii 100),
    funding-pool: uint,
    max-coverage-percentage: uint,
    income-threshold: uint,
    geographic-restrictions: (list 10 (string-ascii 50)),
    treatment-types: (list 5 (string-ascii 50)),
    active: bool,
    total-beneficiaries: uint
  }
)

(define-map subsidy-applications
  { application-id: uint }
  {
    patient-id: uint,
    subsidy-id: uint,
    treatment-type: (string-ascii 50),
    treatment-cost: uint,
    requested-amount: uint,
    application-block: uint,
    status: (string-ascii 20),
    approved-amount: uint,
    reviewer: (optional principal)
  }
)

(define-map funding-sources
  { source-name: (string-ascii 50) }
  {
    contributor: principal,
    total-contributed: uint,
    allocation-preferences: (list 5 (string-ascii 50)),
    active: bool
  }
)

(define-map treatment-costs
  { treatment-type: (string-ascii 50) }
  {
    base-cost: uint,
    complexity-multiplier: uint,
    regional-adjustments: (list 10 { region: (string-ascii 50), multiplier: uint }),
    insurance-coverage: uint
  }
)

(define-map authorized-reviewers
  { reviewer: principal }
  {
    active: bool,
    specialization: (string-ascii 50),
    approved-applications: uint,
    total-reviews: uint
  }
)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-authorized-reviewer (reviewer principal))
  (default-to false (get active (map-get? authorized-reviewers { reviewer: reviewer })))
)

;; Patient Management Functions
(define-public (register-patient (income-level uint) (geographic-region (string-ascii 50)) (age uint) (medical-need-score uint))
  (let
    (
      (patient-id (var-get next-patient-id))
    )
    (asserts! (> age u0) ERR-INVALID-INPUT)
    (asserts! (<= medical-need-score u100) ERR-INVALID-INPUT)
    (asserts! (> (len geographic-region) u0) ERR-INVALID-INPUT)

    (map-set patients
      { patient-id: patient-id }
      {
        wallet: tx-sender,
        income-level: income-level,
        geographic-region: geographic-region,
        age: age,
        medical-need-score: medical-need-score,
        subsidies-received: u0,
        total-treatments: u0,
        active: true
      }
    )

    (var-set next-patient-id (+ patient-id u1))
    (ok patient-id)
  )
)

;; Subsidy Program Management
(define-public (create-subsidy-program
  (program-name (string-ascii 100))
  (funding-pool uint)
  (max-coverage-percentage uint)
  (income-threshold uint)
  (geographic-restrictions (list 10 (string-ascii 50)))
  (treatment-types (list 5 (string-ascii 50))))
  (let
    (
      (subsidy-id (var-get next-subsidy-id))
    )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> funding-pool u0) ERR-INVALID-INPUT)
    (asserts! (<= max-coverage-percentage u100) ERR-INVALID-INPUT)
    (asserts! (> income-threshold u0) ERR-INVALID-INPUT)

    (map-set subsidy-programs
      { subsidy-id: subsidy-id }
      {
        program-name: program-name,
        funding-pool: funding-pool,
        max-coverage-percentage: max-coverage-percentage,
        income-threshold: income-threshold,
        geographic-restrictions: geographic-restrictions,
        treatment-types: treatment-types,
        active: true,
        total-beneficiaries: u0
      }
    )

    (var-set next-subsidy-id (+ subsidy-id u1))
    (ok subsidy-id)
  )
)

;; Application Management Functions
(define-public (apply-for-subsidy (patient-id uint) (subsidy-id uint) (treatment-type (string-ascii 50)) (treatment-cost uint))
  (let
    (
      (application-id (var-get next-application-id))
      (patient (unwrap! (map-get? patients { patient-id: patient-id }) ERR-PATIENT-NOT-FOUND))
      (subsidy (unwrap! (map-get? subsidy-programs { subsidy-id: subsidy-id }) ERR-SUBSIDY-NOT-FOUND))
      (eligibility-check (check-eligibility patient subsidy treatment-type))
      (requested-amount (calculate-subsidy-amount treatment-cost (get max-coverage-percentage subsidy) (get income-level patient)))
    )
    (asserts! (is-eq tx-sender (get wallet patient)) ERR-NOT-AUTHORIZED)
    (asserts! (get active subsidy) ERR-SUBSIDY-NOT-FOUND)
    (asserts! eligibility-check ERR-ELIGIBILITY-FAILED)
    (asserts! (> treatment-cost u0) ERR-INVALID-INPUT)
    (asserts! (<= requested-amount (get funding-pool subsidy)) ERR-INSUFFICIENT-FUNDS)

    (map-set subsidy-applications
      { application-id: application-id }
      {
        patient-id: patient-id,
        subsidy-id: subsidy-id,
        treatment-type: treatment-type,
        treatment-cost: treatment-cost,
        requested-amount: requested-amount,
        application-block: block-height,
        status: "pending",
        approved-amount: u0,
        reviewer: none
      }
    )

    (var-set next-application-id (+ application-id u1))
    (ok application-id)
  )
)

(define-private (check-eligibility (patient (tuple (wallet principal) (income-level uint) (geographic-region (string-ascii 50)) (age uint) (medical-need-score uint) (subsidies-received uint) (total-treatments uint) (active bool))) (subsidy (tuple (program-name (string-ascii 100)) (funding-pool uint) (max-coverage-percentage uint) (income-threshold uint) (geographic-restrictions (list 10 (string-ascii 50))) (treatment-types (list 5 (string-ascii 50))) (active bool) (total-beneficiaries uint))) (treatment-type (string-ascii 50)))
  (let
    (
      (income-eligible (<= (get income-level patient) (get income-threshold subsidy)))
      (geographic-eligible (is-some (index-of (get geographic-restrictions subsidy) (get geographic-region patient))))
      (treatment-eligible (is-some (index-of (get treatment-types subsidy) treatment-type)))
    )
    (and income-eligible (or geographic-eligible (is-eq (len (get geographic-restrictions subsidy)) u0)) treatment-eligible)
  )
)

(define-private (calculate-subsidy-amount (treatment-cost uint) (max-coverage uint) (income-level uint))
  (let
    (
      (income-factor (if (<= income-level u30000) u100
                      (if (<= income-level u50000) u80
                        (if (<= income-level u75000) u60
                          u40))))
      (coverage-percentage (/ (* max-coverage income-factor) u100))
    )
    (/ (* treatment-cost coverage-percentage) u100)
  )
)

(define-public (review-application (application-id uint) (approved bool) (approved-amount uint))
  (let
    (
      (application (unwrap! (map-get? subsidy-applications { application-id: application-id }) ERR-INVALID-INPUT))
      (subsidy (unwrap! (map-get? subsidy-programs { subsidy-id: (get subsidy-id application) }) ERR-SUBSIDY-NOT-FOUND))
    )
    (asserts! (is-authorized-reviewer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status application) "pending") ERR-INVALID-INPUT)
    (asserts! (<= approved-amount (get requested-amount application)) ERR-INVALID-INPUT)

    (map-set subsidy-applications
      { application-id: application-id }
      (merge application {
        status: (if approved "approved" "rejected"),
        approved-amount: approved-amount,
        reviewer: (some tx-sender)
      })
    )

    ;; Update subsidy program funding if approved
    (if approved
      (map-set subsidy-programs
        { subsidy-id: (get subsidy-id application) }
        (merge subsidy {
          funding-pool: (- (get funding-pool subsidy) approved-amount),
          total-beneficiaries: (+ (get total-beneficiaries subsidy) u1)
        })
      )
      true
    )

    (ok approved)
  )
)

;; Funding Management Functions
(define-public (contribute-funding (source-name (string-ascii 50)) (amount uint) (allocation-preferences (list 5 (string-ascii 50))))
  (begin
    (asserts! (> amount u0) ERR-INVALID-INPUT)

    (map-set funding-sources
      { source-name: source-name }
      {
        contributor: tx-sender,
        total-contributed: (+ (default-to u0 (get total-contributed (map-get? funding-sources { source-name: source-name }))) amount),
        allocation-preferences: allocation-preferences,
        active: true
      }
    )

    (var-set total-fund-balance (+ (var-get total-fund-balance) amount))
    (ok true)
  )
)

(define-public (set-treatment-cost (treatment-type (string-ascii 50)) (base-cost uint) (complexity-multiplier uint) (insurance-coverage uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> base-cost u0) ERR-INVALID-INPUT)
    (asserts! (> complexity-multiplier u0) ERR-INVALID-INPUT)
    (asserts! (<= insurance-coverage u100) ERR-INVALID-INPUT)

    (map-set treatment-costs
      { treatment-type: treatment-type }
      {
        base-cost: base-cost,
        complexity-multiplier: complexity-multiplier,
        regional-adjustments: (list),
        insurance-coverage: insurance-coverage
      }
    )
    (ok true)
  )
)

;; Provider Management Functions
(define-public (register-reviewer (reviewer principal) (specialization (string-ascii 50)))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-set authorized-reviewers
      { reviewer: reviewer }
      {
        active: true,
        specialization: specialization,
        approved-applications: u0,
        total-reviews: u0
      }
    )
    (ok true)
  )
)

;; Analytics Functions
(define-public (calculate-access-equity-score (geographic-region (string-ascii 50)))
  (let
    (
      ;; This would calculate equity metrics for a region
      ;; Simplified implementation
      (base-score u75)
    )
    (ok base-score)
  )
)

(define-public (get-funding-distribution)
  (ok {
    total-balance: (var-get total-fund-balance),
    active-programs: (var-get next-subsidy-id),
    total-applications: (var-get next-application-id)
  })
)

;; Read-only Functions
(define-read-only (get-patient (patient-id uint))
  (map-get? patients { patient-id: patient-id })
)

(define-read-only (get-subsidy-program (subsidy-id uint))
  (map-get? subsidy-programs { subsidy-id: subsidy-id })
)

(define-read-only (get-application (application-id uint))
  (map-get? subsidy-applications { application-id: application-id })
)

(define-read-only (get-funding-source (source-name (string-ascii 50)))
  (map-get? funding-sources { source-name: source-name })
)

(define-read-only (get-treatment-cost (treatment-type (string-ascii 50)))
  (map-get? treatment-costs { treatment-type: treatment-type })
)

(define-read-only (get-reviewer-info (reviewer principal))
  (map-get? authorized-reviewers { reviewer: reviewer })
)

(define-read-only (get-contract-stats)
  {
    next-patient-id: (var-get next-patient-id),
    next-subsidy-id: (var-get next-subsidy-id),
    total-fund-balance: (var-get total-fund-balance),
    next-application-id: (var-get next-application-id)
  }
)

(define-read-only (estimate-subsidy-eligibility (patient-id uint) (subsidy-id uint) (treatment-type (string-ascii 50)))
  (let
    (
      (patient (unwrap! (map-get? patients { patient-id: patient-id }) ERR-PATIENT-NOT-FOUND))
      (subsidy (unwrap! (map-get? subsidy-programs { subsidy-id: subsidy-id }) ERR-SUBSIDY-NOT-FOUND))
    )
    (ok (check-eligibility patient subsidy treatment-type))
  )
)
