;; RainDAO Governance Contract
;; Decentralized governance system for rainforest conservation DAO
;; Manages member registration, proposal creation, voting, and treasury operations

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_MEMBER (err u101))
(define-constant ERR_INVALID_PROPOSAL (err u102))
(define-constant ERR_ALREADY_VOTED (err u103))
(define-constant ERR_PROPOSAL_NOT_ACTIVE (err u104))
(define-constant ERR_INSUFFICIENT_STAKE (err u105))
(define-constant ERR_ALREADY_MEMBER (err u106))
(define-constant ERR_PROPOSAL_EXPIRED (err u107))
(define-constant ERR_INVALID_AMOUNT (err u108))
(define-constant ERR_INSUFFICIENT_BALANCE (err u109))

;; Minimum stake required to become a member (in micro STX)
(define-constant MIN_MEMBER_STAKE u1000000) ;; 1 STX
(define-constant MIN_PROPOSAL_STAKE u5000000) ;; 5 STX
(define-constant PROPOSAL_DURATION u1440) ;; blocks (~10 days)
(define-constant VOTING_QUORUM u30) ;; 30% of total voting power

;; Data structures
(define-map members 
  { address: principal }
  {
    stake: uint,
    voting-power: uint,
    join-block: uint,
    reputation-score: uint,
    is-active: bool
  }
)

(define-map proposals
  { proposal-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    funding-amount: uint,
    start-block: uint,
    end-block: uint,
    votes-for: uint,
    votes-against: uint,
    total-votes: uint,
    executed: bool,
    approved: bool
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { 
    vote: bool, 
    voting-power: uint,
    timestamp: uint
  }
)

(define-map member-contributions
  { member: principal }
  {
    total-contributions: uint,
    projects-supported: uint,
    last-activity: uint
  }
)

;; Global variables
(define-data-var proposal-counter uint u0)
(define-data-var total-members uint u0)
(define-data-var total-voting-power uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var dao-active bool true)

;; Member registration function
(define-public (register-member (stake-amount uint))
  (let (
    (caller tx-sender)
    (current-member (map-get? members { address: caller }))
  )
    (asserts! (is-none current-member) ERR_ALREADY_MEMBER)
    (asserts! (>= stake-amount MIN_MEMBER_STAKE) ERR_INSUFFICIENT_STAKE)
    (asserts! (>= (stx-get-balance caller) stake-amount) ERR_INSUFFICIENT_BALANCE)
    
    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount caller (as-contract tx-sender)))
    
    ;; Calculate voting power (stake + bonus for early adoption)
    (let (
      (voting-power (+ stake-amount (/ stake-amount u10))) ;; 10% bonus
    )
      ;; Register member
      (map-set members { address: caller }
        {
          stake: stake-amount,
          voting-power: voting-power,
          join-block: stacks-block-height,
          reputation-score: u100, ;; Starting reputation
          is-active: true
        }
      )
      
      ;; Update global counters
      (var-set total-members (+ (var-get total-members) u1))
      (var-set total-voting-power (+ (var-get total-voting-power) voting-power))
      
      ;; Initialize member contributions
      (map-set member-contributions { member: caller }
        {
          total-contributions: u0,
          projects-supported: u0,
          last-activity: stacks-block-height
        }
      )
      
      (ok voting-power)
    )
  )
)

;; Proposal creation function
(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (funding-amount uint)
)
  (let (
    (caller tx-sender)
    (member-data (unwrap! (map-get? members { address: caller }) ERR_NOT_MEMBER))
    (proposal-id (+ (var-get proposal-counter) u1))
  )
    (asserts! (get is-active member-data) ERR_NOT_MEMBER)
    (asserts! (>= (get stake member-data) MIN_PROPOSAL_STAKE) ERR_INSUFFICIENT_STAKE)
    (asserts! (> funding-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (var-get dao-active) ERR_UNAUTHORIZED)
    
    ;; Create proposal
    (map-set proposals { proposal-id: proposal-id }
      {
        creator: caller,
        title: title,
        description: description,
        funding-amount: funding-amount,
        start-block: stacks-block-height,
        end-block: (+ stacks-block-height PROPOSAL_DURATION),
        votes-for: u0,
        votes-against: u0,
        total-votes: u0,
        executed: false,
        approved: false
      }
    )
    
    ;; Update proposal counter
    (var-set proposal-counter proposal-id)
    
    ;; Update member activity
    (map-set member-contributions { member: caller }
      (merge 
        (default-to 
          { total-contributions: u0, projects-supported: u0, last-activity: u0 }
          (map-get? member-contributions { member: caller })
        )
        { last-activity: stacks-block-height }
      )
    )
    
    (ok proposal-id)
  )
)

;; Voting function
(define-public (cast-vote (proposal-id uint) (vote bool))
  (let (
    (caller tx-sender)
    (member-data (unwrap! (map-get? members { address: caller }) ERR_NOT_MEMBER))
    (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_INVALID_PROPOSAL))
    (existing-vote (map-get? votes { proposal-id: proposal-id, voter: caller }))
    (voting-power (get voting-power member-data))
  )
    (asserts! (get is-active member-data) ERR_NOT_MEMBER)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    (asserts! (<= stacks-block-height (get end-block proposal-data)) ERR_PROPOSAL_EXPIRED)
    (asserts! (not (get executed proposal-data)) ERR_PROPOSAL_NOT_ACTIVE)
    
    ;; Record vote
    (map-set votes { proposal-id: proposal-id, voter: caller }
      {
        vote: vote,
        voting-power: voting-power,
        timestamp: stacks-block-height
      }
    )
    
    ;; Update proposal vote counts
    (let (
      (new-votes-for (if vote (+ (get votes-for proposal-data) voting-power) (get votes-for proposal-data)))
      (new-votes-against (if vote (get votes-against proposal-data) (+ (get votes-against proposal-data) voting-power)))
      (new-total-votes (+ (get total-votes proposal-data) voting-power))
    )
      (map-set proposals { proposal-id: proposal-id }
        (merge proposal-data
          {
            votes-for: new-votes-for,
            votes-against: new-votes-against,
            total-votes: new-total-votes
          }
        )
      )
    )
    
    ;; Update member activity and reputation
    (let (
      (contribution-data (default-to 
        { total-contributions: u0, projects-supported: u0, last-activity: u0 }
        (map-get? member-contributions { member: caller })
      ))
    )
      (map-set member-contributions { member: caller }
        (merge contribution-data { last-activity: stacks-block-height })
      )
      
      ;; Increase reputation for voting participation
      (map-set members { address: caller }
        (merge member-data 
          { reputation-score: (+ (get reputation-score member-data) u5) }
        )
      )
    )
    
    (ok voting-power)
  )
)

;; Execute approved proposal
(define-public (execute-proposal (proposal-id uint))
  (let (
    (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_INVALID_PROPOSAL))
    (total-power (var-get total-voting-power))
    (quorum-threshold (/ (* total-power VOTING_QUORUM) u100))
    (approval-threshold (/ (get total-votes proposal-data) u2)) ;; 50% + 1
  )
    (asserts! (> stacks-block-height (get end-block proposal-data)) ERR_PROPOSAL_NOT_ACTIVE)
    (asserts! (not (get executed proposal-data)) ERR_PROPOSAL_NOT_ACTIVE)
    (asserts! (>= (get total-votes proposal-data) quorum-threshold) ERR_INSUFFICIENT_STAKE)
    
    (let (
      (approved (> (get votes-for proposal-data) approval-threshold))
      (funding-amount (get funding-amount proposal-data))
    )
      ;; Mark proposal as executed
      (map-set proposals { proposal-id: proposal-id }
        (merge proposal-data
          {
            executed: true,
            approved: approved
          }
        )
      )
      
      ;; If approved and we have funds, transfer to creator
      (if (and approved (>= (var-get treasury-balance) funding-amount))
        (begin
          (try! (as-contract (stx-transfer? funding-amount tx-sender (get creator proposal-data))))
          (var-set treasury-balance (- (var-get treasury-balance) funding-amount))
          
          ;; Update creator's contribution record
          (let (
            (creator (get creator proposal-data))
            (contrib-data (default-to
              { total-contributions: u0, projects-supported: u0, last-activity: u0 }
              (map-get? member-contributions { member: creator })
            ))
          )
            (map-set member-contributions { member: creator }
              (merge contrib-data
                {
                  total-contributions: (+ (get total-contributions contrib-data) funding-amount),
                  projects-supported: (+ (get projects-supported contrib-data) u1),
                  last-activity: stacks-block-height
                }
              )
            )
          )
        )
        true
      )
      
      (ok approved)
    )
  )
)

;; Treasury management - add funds
(define-public (contribute-to-treasury (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (ok amount)
  )
)

;; Read-only functions
(define-read-only (get-member-info (member principal))
  (map-get? members { address: member })
)

(define-read-only (get-proposal-info (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-vote-info (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-member-contributions (member principal))
  (map-get? member-contributions { member: member })
)

(define-read-only (get-dao-stats)
  {
    total-members: (var-get total-members),
    total-voting-power: (var-get total-voting-power),
    treasury-balance: (var-get treasury-balance),
    proposal-count: (var-get proposal-counter),
    dao-active: (var-get dao-active)
  }
)

(define-read-only (is-proposal-active (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal-data 
      (and 
        (<= stacks-block-height (get end-block proposal-data))
        (not (get executed proposal-data))
      )
    false
  )
)

;; Admin functions (contract owner only)
(define-public (set-dao-active (active bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set dao-active active)
    (ok active)
  )
)

