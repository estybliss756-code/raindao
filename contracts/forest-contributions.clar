;; Forest Contributions Contract
;; Tracks and rewards environmental conservation activities in the RainDAO ecosystem
;; Manages contribution recording, verification, reward distribution, and impact measurement

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_NOT_FOUND (err u201))
(define-constant ERR_INVALID_AMOUNT (err u202))
(define-constant ERR_ALREADY_EXISTS (err u203))
(define-constant ERR_INVALID_PARAMETERS (err u204))
(define-constant ERR_INSUFFICIENT_BALANCE (err u205))
(define-constant ERR_ALREADY_VERIFIED (err u206))
(define-constant ERR_VERIFICATION_FAILED (err u207))
(define-constant ERR_REWARD_CLAIMED (err u208))
(define-constant ERR_PROJECT_INACTIVE (err u209))

;; Conservation activity types
(define-constant ACTIVITY_REFORESTATION u1)
(define-constant ACTIVITY_FOREST_PROTECTION u2)
(define-constant ACTIVITY_WILDLIFE_CONSERVATION u3)
(define-constant ACTIVITY_CARBON_MONITORING u4)
(define-constant ACTIVITY_COMMUNITY_EDUCATION u5)

;; Reward multipliers per activity type (basis points, 10000 = 100%)
(define-constant REFORESTATION_MULTIPLIER u15000) ;; 150%
(define-constant PROTECTION_MULTIPLIER u12000) ;; 120%
(define-constant WILDLIFE_MULTIPLIER u10000) ;; 100%
(define-constant CARBON_MULTIPLIER u8000) ;; 80%
(define-constant EDUCATION_MULTIPLIER u6000) ;; 60%

;; Verification requirements
(define-constant MIN_VERIFICATIONS u3)
(define-constant MAX_REWARD_AMOUNT u50000000) ;; 50 STX max reward
(define-constant BASE_REWARD_RATE u1000) ;; Base reward per unit of impact

;; Data structures
(define-map conservation-projects
  { project-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 300),
    location: (string-ascii 100),
    activity-type: uint,
    target-impact: uint, ;; Expected impact units (hectares, trees, etc.)
    actual-impact: uint, ;; Verified impact units
    start-date: uint, ;; Block height
    end-date: uint, ;; Block height
    status: uint, ;; 1=active, 2=completed, 3=verified, 4=rewarded
    verification-count: uint,
    total-reward: uint,
    created-at: uint
  }
)

(define-map project-contributions
  { project-id: uint, contributor: principal }
  {
    contribution-type: uint, ;; Same as activity types
    impact-units: uint, ;; Amount contributed (hectares, trees, etc.)
    evidence-hash: (string-ascii 64), ;; IPFS hash or similar
    timestamp: uint,
    verified: bool,
    reward-amount: uint,
    reward-claimed: bool
  }
)

(define-map project-verifications
  { project-id: uint, verifier: principal }
  {
    verification-score: uint, ;; 0-100 score
    verified-impact: uint,
    verification-notes: (string-ascii 200),
    timestamp: uint,
    reward-given: uint
  }
)

(define-map contributor-stats
  { contributor: principal }
  {
    total-projects: uint,
    total-impact: uint,
    total-rewards: uint,
    reputation-score: uint,
    last-activity: uint,
    verified-contributions: uint
  }
)

(define-map environmental-impact
  { project-id: uint }
  {
    carbon-sequestered: uint, ;; tons of CO2
    biodiversity-score: uint, ;; 0-1000 scale
    forest-area: uint, ;; hectares
    trees-planted: uint,
    communities-involved: uint,
    sustainability-rating: uint ;; 0-100 scale
  }
)

;; Global variables
(define-data-var project-counter uint u0)
(define-data-var total-contributions uint u0)
(define-data-var total-impact-units uint u0)
(define-data-var total-rewards-distributed uint u0)
(define-data-var reward-pool-balance uint u0)
(define-data-var system-active bool true)

;; Project creation function
(define-public (create-conservation-project
  (title (string-ascii 100))
  (description (string-ascii 300))
  (location (string-ascii 100))
  (activity-type uint)
  (target-impact uint)
  (duration-blocks uint)
)
  (let (
    (caller tx-sender)
    (project-id (+ (var-get project-counter) u1))
  )
    (asserts! (var-get system-active) ERR_UNAUTHORIZED)
    (asserts! (> target-impact u0) ERR_INVALID_PARAMETERS)
    (asserts! (and (>= activity-type u1) (<= activity-type u5)) ERR_INVALID_PARAMETERS)
    (asserts! (> (len title) u0) ERR_INVALID_PARAMETERS)
    (asserts! (> duration-blocks u0) ERR_INVALID_PARAMETERS)
    
    ;; Create project
    (map-set conservation-projects { project-id: project-id }
      {
        creator: caller,
        title: title,
        description: description,
        location: location,
        activity-type: activity-type,
        target-impact: target-impact,
        actual-impact: u0,
        start-date: stacks-block-height,
        end-date: (+ stacks-block-height duration-blocks),
        status: u1, ;; Active
        verification-count: u0,
        total-reward: u0,
        created-at: stacks-block-height
      }
    )
    
    ;; Initialize environmental impact tracking
    (map-set environmental-impact { project-id: project-id }
      {
        carbon-sequestered: u0,
        biodiversity-score: u0,
        forest-area: u0,
        trees-planted: u0,
        communities-involved: u0,
        sustainability-rating: u0
      }
    )
    
    ;; Update global counter
    (var-set project-counter project-id)
    
    ;; Initialize contributor stats if new
    (if (is-none (map-get? contributor-stats { contributor: caller }))
      (map-set contributor-stats { contributor: caller }
        {
          total-projects: u1,
          total-impact: u0,
          total-rewards: u0,
          reputation-score: u100,
          last-activity: stacks-block-height,
          verified-contributions: u0
        }
      )
      (let (
        (stats (unwrap-panic (map-get? contributor-stats { contributor: caller })))
      )
        (map-set contributor-stats { contributor: caller }
          (merge stats
            {
              total-projects: (+ (get total-projects stats) u1),
              last-activity: stacks-block-height
            }
          )
        )
      )
    )
    
    (ok project-id)
  )
)

;; Record contribution to project
(define-public (record-contribution
  (project-id uint)
  (impact-units uint)
  (evidence-hash (string-ascii 64))
)
  (let (
    (caller tx-sender)
    (project (unwrap! (map-get? conservation-projects { project-id: project-id }) ERR_NOT_FOUND))
    (existing-contribution (map-get? project-contributions { project-id: project-id, contributor: caller }))
  )
    (asserts! (is-eq (get status project) u1) ERR_PROJECT_INACTIVE) ;; Project must be active
    (asserts! (<= stacks-block-height (get end-date project)) ERR_PROJECT_INACTIVE)
    (asserts! (> impact-units u0) ERR_INVALID_AMOUNT)
    (asserts! (> (len evidence-hash) u0) ERR_INVALID_PARAMETERS)
    
    ;; Record or update contribution
    (if (is-some existing-contribution)
      (let (
        (current-contrib (unwrap-panic existing-contribution))
      )
        (map-set project-contributions { project-id: project-id, contributor: caller }
          (merge current-contrib
            {
              impact-units: (+ (get impact-units current-contrib) impact-units),
              evidence-hash: evidence-hash,
              timestamp: stacks-block-height
            }
          )
        )
      )
      (map-set project-contributions { project-id: project-id, contributor: caller }
        {
          contribution-type: (get activity-type project),
          impact-units: impact-units,
          evidence-hash: evidence-hash,
          timestamp: stacks-block-height,
          verified: false,
          reward-amount: u0,
          reward-claimed: false
        }
      )
    )
    
    ;; Update project's actual impact
    (map-set conservation-projects { project-id: project-id }
      (merge project
        { actual-impact: (+ (get actual-impact project) impact-units) }
      )
    )
    
    ;; Update global stats
    (var-set total-contributions (+ (var-get total-contributions) u1))
    (var-set total-impact-units (+ (var-get total-impact-units) impact-units))
    
    ;; Update contributor stats
    (let (
      (stats (default-to
        {
          total-projects: u0,
          total-impact: u0,
          total-rewards: u0,
          reputation-score: u100,
          last-activity: u0,
          verified-contributions: u0
        }
        (map-get? contributor-stats { contributor: caller })
      ))
    )
      (map-set contributor-stats { contributor: caller }
        (merge stats
          {
            total-impact: (+ (get total-impact stats) impact-units),
            last-activity: stacks-block-height
          }
        )
      )
    )
    
    (ok impact-units)
  )
)

;; Verify project contribution (by community members)
(define-public (verify-contribution
  (project-id uint)
  (contributor principal)
  (verification-score uint)
  (verified-impact uint)
  (notes (string-ascii 200))
)
  (let (
    (caller tx-sender)
    (project (unwrap! (map-get? conservation-projects { project-id: project-id }) ERR_NOT_FOUND))
    (contribution (unwrap! (map-get? project-contributions { project-id: project-id, contributor: contributor }) ERR_NOT_FOUND))
    (existing-verification (map-get? project-verifications { project-id: project-id, verifier: caller }))
  )
    (asserts! (is-none existing-verification) ERR_ALREADY_VERIFIED)
    (asserts! (not (is-eq caller contributor)) ERR_UNAUTHORIZED) ;; Can't verify own contribution
    (asserts! (and (>= verification-score u0) (<= verification-score u100)) ERR_INVALID_PARAMETERS)
    (asserts! (>= verified-impact u0) ERR_INVALID_PARAMETERS)
    
    ;; Record verification
    (map-set project-verifications { project-id: project-id, verifier: caller }
      {
        verification-score: verification-score,
        verified-impact: verified-impact,
        verification-notes: notes,
        timestamp: stacks-block-height,
        reward-given: u0
      }
    )
    
    ;; Update project verification count
    (let (
      (new-verification-count (+ (get verification-count project) u1))
    )
      (map-set conservation-projects { project-id: project-id }
        (merge project
          { verification-count: new-verification-count }
        )
      )
      
      ;; If minimum verifications reached, mark contribution as verified
      (if (>= new-verification-count MIN_VERIFICATIONS)
        (begin
          (map-set project-contributions { project-id: project-id, contributor: contributor }
            (merge contribution { verified: true })
          )
          
          ;; Update contributor stats
          (let (
            (stats (unwrap-panic (map-get? contributor-stats { contributor: contributor })))
          )
            (map-set contributor-stats { contributor: contributor }
              (merge stats
                {
                  verified-contributions: (+ (get verified-contributions stats) u1),
                  reputation-score: (+ (get reputation-score stats) u10)
                }
              )
            )
          )
        )
        true
      )
    )
    
    ;; Reward verifier with small amount
    (let (
      (verifier-reward u100000) ;; 0.1 STX
    )
      (if (and (> (var-get reward-pool-balance) verifier-reward) (> verification-score u70))
        (begin
          (try! (as-contract (stx-transfer? verifier-reward tx-sender caller)))
          (var-set reward-pool-balance (- (var-get reward-pool-balance) verifier-reward))
          (map-set project-verifications { project-id: project-id, verifier: caller }
            (merge (unwrap-panic (map-get? project-verifications { project-id: project-id, verifier: caller }))
              { reward-given: verifier-reward }
            )
          )
        )
        true
      )
    )
    
    (ok verification-score)
  )
)

;; Calculate and claim rewards for verified contributions
(define-public (claim-contribution-reward (project-id uint))
  (let (
    (caller tx-sender)
    (project (unwrap! (map-get? conservation-projects { project-id: project-id }) ERR_NOT_FOUND))
    (contribution (unwrap! (map-get? project-contributions { project-id: project-id, contributor: caller }) ERR_NOT_FOUND))
  )
    (asserts! (get verified contribution) ERR_VERIFICATION_FAILED)
    (asserts! (not (get reward-claimed contribution)) ERR_REWARD_CLAIMED)
    
    ;; Calculate reward based on activity type and impact
    (let (
      (activity-type (get contribution-type contribution))
      (impact-units (get impact-units contribution))
      (multiplier (get-activity-multiplier activity-type))
      (base-reward (* impact-units BASE_REWARD_RATE))
      (total-reward (min-value (/ (* base-reward multiplier) u10000) MAX_REWARD_AMOUNT))
    )
      (asserts! (>= (var-get reward-pool-balance) total-reward) ERR_INSUFFICIENT_BALANCE)
      
      ;; Transfer reward
      (try! (as-contract (stx-transfer? total-reward tx-sender caller)))
      
      ;; Update contribution record
      (map-set project-contributions { project-id: project-id, contributor: caller }
        (merge contribution
          {
            reward-amount: total-reward,
            reward-claimed: true
          }
        )
      )
      
      ;; Update global and project stats
      (var-set reward-pool-balance (- (var-get reward-pool-balance) total-reward))
      (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) total-reward))
      
      (map-set conservation-projects { project-id: project-id }
        (merge project
          { total-reward: (+ (get total-reward project) total-reward) }
        )
      )
      
      ;; Update contributor stats
      (let (
        (stats (unwrap-panic (map-get? contributor-stats { contributor: caller })))
      )
        (map-set contributor-stats { contributor: caller }
          (merge stats
            {
              total-rewards: (+ (get total-rewards stats) total-reward),
              reputation-score: (+ (get reputation-score stats) u20),
              last-activity: stacks-block-height
            }
          )
        )
      )
      
      (ok total-reward)
    )
  )
)

;; Add funds to reward pool
(define-public (contribute-to-reward-pool (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set reward-pool-balance (+ (var-get reward-pool-balance) amount))
    (ok amount)
  )
)

;; Private helper functions
(define-private (min-value (a uint) (b uint))
  (if (<= a b) a b)
)

(define-private (get-activity-multiplier (activity-type uint))
  (if (is-eq activity-type ACTIVITY_REFORESTATION)
    REFORESTATION_MULTIPLIER
    (if (is-eq activity-type ACTIVITY_FOREST_PROTECTION)
      PROTECTION_MULTIPLIER
      (if (is-eq activity-type ACTIVITY_WILDLIFE_CONSERVATION)
        WILDLIFE_MULTIPLIER
        (if (is-eq activity-type ACTIVITY_CARBON_MONITORING)
          CARBON_MULTIPLIER
          EDUCATION_MULTIPLIER
        )
      )
    )
  )
)

;; Read-only functions
(define-read-only (get-project-info (project-id uint))
  (map-get? conservation-projects { project-id: project-id })
)

(define-read-only (get-contribution-info (project-id uint) (contributor principal))
  (map-get? project-contributions { project-id: project-id, contributor: contributor })
)

(define-read-only (get-verification-info (project-id uint) (verifier principal))
  (map-get? project-verifications { project-id: project-id, verifier: verifier })
)

(define-read-only (get-contributor-stats (contributor principal))
  (map-get? contributor-stats { contributor: contributor })
)

(define-read-only (get-environmental-impact (project-id uint))
  (map-get? environmental-impact { project-id: project-id })
)

(define-read-only (get-system-stats)
  {
    total-projects: (var-get project-counter),
    total-contributions: (var-get total-contributions),
    total-impact-units: (var-get total-impact-units),
    total-rewards-distributed: (var-get total-rewards-distributed),
    reward-pool-balance: (var-get reward-pool-balance),
    system-active: (var-get system-active)
  }
)

(define-read-only (calculate-potential-reward (activity-type uint) (impact-units uint))
  (let (
    (multiplier (get-activity-multiplier activity-type))
    (base-reward (* impact-units BASE_REWARD_RATE))
    (total-reward (min-value (/ (* base-reward multiplier) u10000) MAX_REWARD_AMOUNT))
  )
    total-reward
  )
)

;; Admin functions
(define-public (set-system-active (active bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set system-active active)
    (ok active)
  )
)

(define-public (update-environmental-impact
  (project-id uint)
  (carbon-sequestered uint)
  (biodiversity-score uint)
  (forest-area uint)
  (trees-planted uint)
  (communities-involved uint)
  (sustainability-rating uint)
)
  (let (
    (project (unwrap! (map-get? conservation-projects { project-id: project-id }) ERR_NOT_FOUND))
  )
    ;; Only project creator or contract owner can update
    (asserts! (or (is-eq tx-sender (get creator project)) (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
    
    (map-set environmental-impact { project-id: project-id }
      {
        carbon-sequestered: carbon-sequestered,
        biodiversity-score: biodiversity-score,
        forest-area: forest-area,
        trees-planted: trees-planted,
        communities-involved: communities-involved,
        sustainability-rating: sustainability-rating
      }
    )
    
    (ok true)
  )
)

