;; Governance Token Contract
;; Governance token contract that allows holders to vote on protocol parameters, 
;; fee structures, and new strategy implementations.

;; Token Definition
(define-fungible-token yield-gov-token)

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant TOKEN-NAME "Yield Governance Token")
(define-constant TOKEN-SYMBOL "YGT")
(define-constant TOKEN-DECIMALS u6)
(define-constant TOTAL-SUPPLY u100000000000000) ;; 100M tokens with 6 decimals

;; Error Codes
(define-constant ERR-UNAUTHORIZED (err u300))
(define-constant ERR-INSUFFICIENT-BALANCE (err u301))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u302))
(define-constant ERR-VOTING-CLOSED (err u303))
(define-constant ERR-ALREADY-VOTED (err u304))
(define-constant ERR-PROPOSAL-EXPIRED (err u305))
(define-constant ERR-INSUFFICIENT-TOKENS (err u306))
(define-constant ERR-EXECUTION-FAILED (err u307))
(define-constant ERR-INVALID-PROPOSAL (err u308))

;; Proposal Constants
(define-constant MIN-PROPOSAL-TOKENS u1000000000) ;; 1000 tokens minimum to create proposal
(define-constant MIN-VOTING-PERIOD u1008) ;; ~7 days in blocks
(define-constant MAX-VOTING-PERIOD u4032) ;; ~28 days in blocks
(define-constant QUORUM-THRESHOLD u2000) ;; 20% of total supply
(define-constant APPROVAL-THRESHOLD u5100) ;; 51% approval needed

;; Data Variables
(define-data-var next-proposal-id uint u1)
(define-data-var governance-active bool true)
(define-data-var min-proposal-threshold uint MIN-PROPOSAL-TOKENS)
(define-data-var voting-delay uint u144) ;; ~24 hours in blocks

;; Data Maps
(define-map proposals uint {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-utf8 500),
    proposal-type: (string-ascii 20),
    target-contract: (optional principal),
    function-name: (optional (string-ascii 50)),
    parameters: (optional (string-utf8 200)),
    start-block: uint,
    end-block: uint,
    votes-for: uint,
    votes-against: uint,
    votes-abstain: uint,
    status: (string-ascii 20), ;; "active", "passed", "failed", "executed", "cancelled"
    execution-delay: uint,
    created-at: uint
})

(define-map votes {
    proposal-id: uint,
    voter: principal
} {
    vote: (string-ascii 10), ;; "for", "against", "abstain"
    voting-power: uint,
    timestamp: uint
})

(define-map user-voting-power principal uint)
(define-map delegation principal principal) ;; delegator -> delegate
(define-map delegate-power principal uint) ;; total delegated power per delegate
(define-map proposal-execution uint {
    executed: bool,
    execution-block: uint,
    execution-result: (optional bool)
})

;; Token holders who can create proposals
(define-map authorized-proposers principal bool)

;; Staking for enhanced voting power
(define-map staked-tokens principal {
    amount: uint,
    staked-at: uint,
    lock-period: uint
})

;; Private Functions

(define-private (get-voting-power (user principal))
    (let (
        (token-balance (ft-get-balance yield-gov-token user))
        (staked-info (map-get? staked-tokens user))
        (delegated-power (default-to u0 (map-get? delegate-power user)))
        (base-power token-balance)
    )
        (match staked-info
            staked 
                (let (
                    (staked-amount (get amount staked))
                    (multiplier (get-stake-multiplier (get lock-period staked)))
                )
                    (+ base-power (* staked-amount multiplier) delegated-power)
                )
            (+ base-power delegated-power)
        )
    )
)

(define-private (get-stake-multiplier (lock-period uint))
    (if (>= lock-period u52560) ;; ~1 year
        u3 ;; 3x multiplier
        (if (>= lock-period u26280) ;; ~6 months
            u2 ;; 2x multiplier
            u1 ;; 1x multiplier
        )
    )
)

(define-private (is-proposal-active (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal 
            (and 
                (is-eq (get status proposal) "active")
                (>= block-height (get start-block proposal))
                (<= block-height (get end-block proposal))
            )
        false
    )
)

(define-private (calculate-quorum (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) u0))
        (total-votes (+ (+ (get votes-for proposal) (get votes-against proposal)) (get votes-abstain proposal)))
        (required-quorum (/ (* (ft-get-supply yield-gov-token) QUORUM-THRESHOLD) u10000))
    )
        (>= total-votes required-quorum)
    )
)

(define-private (has-voted (proposal-id uint) (voter principal))
    (is-some (map-get? votes {proposal-id: proposal-id, voter: voter}))
)

(define-private (is-authorized-proposer (user principal))
    (or 
        (is-eq user CONTRACT-OWNER)
        (default-to false (map-get? authorized-proposers user))
        (>= (get-voting-power user) (var-get min-proposal-threshold))
    )
)

(define-private (validate-proposal-parameters (proposal-type (string-ascii 20)) (target (optional principal)))
    (if (is-eq proposal-type "parameter-change")
        (is-some target)
        true
    )
)

;; Read-Only Functions

(define-read-only (get-name)
    (ok TOKEN-NAME)
)

(define-read-only (get-symbol)
    (ok TOKEN-SYMBOL)
)

(define-read-only (get-decimals)
    (ok TOKEN-DECIMALS)
)

(define-read-only (get-total-supply)
    (ok (ft-get-supply yield-gov-token))
)

(define-read-only (get-balance (user principal))
    (ok (ft-get-balance yield-gov-token user))
)

(define-read-only (get-voting-power (user principal))
    (ok (get-voting-power user))
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-proposal-status (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal 
            (let (
                (current-block block-height)
                (start-block (get start-block proposal))
                (end-block (get end-block proposal))
                (status (get status proposal))
            )
                (ok {
                    status: status,
                    voting-open: (and (>= current-block start-block) (<= current-block end-block)),
                    quorum-met: (calculate-quorum proposal-id),
                    votes-for: (get votes-for proposal),
                    votes-against: (get votes-against proposal),
                    votes-abstain: (get votes-abstain proposal)
                })
            )
        ERR-PROPOSAL-NOT-FOUND
    )
)

(define-read-only (get-user-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-delegation (delegator principal))
    (map-get? delegation delegator)
)

(define-read-only (get-staked-info (user principal))
    (map-get? staked-tokens user)
)

(define-read-only (calculate-proposal-result (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal 
            (let (
                (votes-for (get votes-for proposal))
                (votes-against (get votes-against proposal))
                (total-decisive-votes (+ votes-for votes-against))
                (approval-rate (if (> total-decisive-votes u0)
                                  (/ (* votes-for u10000) total-decisive-votes)
                                  u0))
            )
                (ok {
                    approval-rate: approval-rate,
                    passing: (and 
                        (>= approval-rate APPROVAL-THRESHOLD)
                        (calculate-quorum proposal-id)
                    ),
                    quorum-met: (calculate-quorum proposal-id)
                })
            )
        ERR-PROPOSAL-NOT-FOUND
    )
)

;; Public Functions

(define-public (mint-tokens (recipient principal) (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (ft-mint? yield-gov-token amount recipient)
    )
)

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (is-eq tx-sender sender) ERR-UNAUTHORIZED)
        (ft-transfer? yield-gov-token amount sender recipient)
    )
)

(define-public (create-proposal 
    (title (string-ascii 100))
    (description (string-utf8 500))
    (proposal-type (string-ascii 20))
    (target-contract (optional principal))
    (function-name (optional (string-ascii 50)))
    (parameters (optional (string-utf8 200)))
    (voting-period uint)
)
    (begin
        (asserts! (var-get governance-active) ERR-UNAUTHORIZED)
        (asserts! (is-authorized-proposer tx-sender) ERR-INSUFFICIENT-TOKENS)
        (asserts! (and (>= voting-period MIN-VOTING-PERIOD) (<= voting-period MAX-VOTING-PERIOD)) ERR-INVALID-PROPOSAL)
        (asserts! (validate-proposal-parameters proposal-type target-contract) ERR-INVALID-PROPOSAL)
        
        (let (
            (proposal-id (var-get next-proposal-id))
            (start-block (+ block-height (var-get voting-delay)))
            (end-block (+ start-block voting-period))
        )
            (map-set proposals proposal-id {
                proposer: tx-sender,
                title: title,
                description: description,
                proposal-type: proposal-type,
                target-contract: target-contract,
                function-name: function-name,
                parameters: parameters,
                start-block: start-block,
                end-block: end-block,
                votes-for: u0,
                votes-against: u0,
                votes-abstain: u0,
                status: "active",
                execution-delay: u0,
                created-at: block-height
            })
            
            (var-set next-proposal-id (+ proposal-id u1))
            
            (ok proposal-id)
        )
    )
)

(define-public (vote (proposal-id uint) (vote-type (string-ascii 10)))
    (begin
        (asserts! (is-proposal-active proposal-id) ERR-VOTING-CLOSED)
        (asserts! (not (has-voted proposal-id tx-sender)) ERR-ALREADY-VOTED)
        (asserts! (or (is-eq vote-type "for") (or (is-eq vote-type "against") (is-eq vote-type "abstain"))) ERR-INVALID-PROPOSAL)
        
        (let (
            (voting-power (get-voting-power tx-sender))
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
        )
            (asserts! (> voting-power u0) ERR-INSUFFICIENT-TOKENS)
            
            ;; Record the vote
            (map-set votes {proposal-id: proposal-id, voter: tx-sender} {
                vote: vote-type,
                voting-power: voting-power,
                timestamp: block-height
            })
            
            ;; Update proposal vote counts
            (let (
                (updated-proposal 
                    (if (is-eq vote-type "for")
                        (merge proposal {votes-for: (+ (get votes-for proposal) voting-power)})
                        (if (is-eq vote-type "against")
                            (merge proposal {votes-against: (+ (get votes-against proposal) voting-power)})
                            (merge proposal {votes-abstain: (+ (get votes-abstain proposal) voting-power)})
                        )
                    )
                )
            )
                (map-set proposals proposal-id updated-proposal)
                (ok true)
            )
        )
    )
)

(define-public (execute-proposal (proposal-id uint))
    (begin
        (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (result (unwrap! (calculate-proposal-result proposal-id) ERR-EXECUTION-FAILED))
            (current-block block-height)
        )
            (asserts! (> current-block (get end-block proposal)) ERR-VOTING-CLOSED)
            (asserts! (is-eq (get status proposal) "active") ERR-EXECUTION-FAILED)
            (asserts! (get passing result) ERR-EXECUTION-FAILED)
            
            ;; Mark proposal as executed
            (map-set proposals proposal-id (merge proposal {status: "executed"}))
            (map-set proposal-execution proposal-id {
                executed: true,
                execution-block: current-block,
                execution-result: (some true)
            })
            
            ;; TODO: Implement actual execution logic based on proposal type
            ;; This would involve calling the target contract with specified parameters
            
            (ok true)
        )
    )
)

(define-public (delegate-voting-power (delegate principal))
    (begin
        (asserts! (not (is-eq tx-sender delegate)) ERR-INVALID-PROPOSAL)
        
        (let (
            (delegator-power (get-voting-power tx-sender))
            (current-delegate (map-get? delegation tx-sender))
        )
            ;; Remove power from current delegate if exists
            (match current-delegate
                existing-delegate
                    (map-set delegate-power existing-delegate 
                        (- (default-to u0 (map-get? delegate-power existing-delegate)) delegator-power))
                true
            )
            
            ;; Set new delegation
            (map-set delegation tx-sender delegate)
            
            ;; Add power to new delegate
            (map-set delegate-power delegate 
                (+ (default-to u0 (map-get? delegate-power delegate)) delegator-power))
            
            (ok true)
        )
    )
)

(define-public (revoke-delegation)
    (begin
        (let (
            (current-delegate (map-get? delegation tx-sender))
            (delegator-power (get-voting-power tx-sender))
        )
            (match current-delegate
                delegate
                    (begin
                        ;; Remove delegation
                        (map-delete delegation tx-sender)
                        
                        ;; Remove power from delegate
                        (map-set delegate-power delegate 
                            (- (default-to u0 (map-get? delegate-power delegate)) delegator-power))
                        
                        (ok true)
                    )
                ERR-UNAUTHORIZED
            )
        )
    )
)

(define-public (stake-tokens (amount uint) (lock-period uint))
    (begin
        (asserts! (>= amount u1000000) ERR-INSUFFICIENT-BALANCE) ;; Minimum 1 token
        (asserts! (>= lock-period u1440) ERR-INVALID-PROPOSAL) ;; Minimum 10 days
        
        (let (
            (current-balance (ft-get-balance yield-gov-token tx-sender))
            (current-staked (default-to {amount: u0, staked-at: u0, lock-period: u0} (map-get? staked-tokens tx-sender)))
        )
            (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
            
            ;; Transfer tokens to contract for staking
            (try! (ft-transfer? yield-gov-token amount tx-sender (as-contract tx-sender)))
            
            ;; Update staked info
            (map-set staked-tokens tx-sender {
                amount: (+ (get amount current-staked) amount),
                staked-at: block-height,
                lock-period: lock-period
            })
            
            (ok true)
        )
    )
)

(define-public (unstake-tokens (amount uint))
    (begin
        (let (
            (staked-info (unwrap! (map-get? staked-tokens tx-sender) ERR-INSUFFICIENT-BALANCE))
            (staked-amount (get amount staked-info))
            (lock-end (+ (get staked-at staked-info) (get lock-period staked-info)))
        )
            (asserts! (>= block-height lock-end) ERR-VOTING-CLOSED) ;; Lock period not ended
            (asserts! (<= amount staked-amount) ERR-INSUFFICIENT-BALANCE)
            
            ;; Update staked info
            (if (is-eq amount staked-amount)
                (map-delete staked-tokens tx-sender) ;; Remove if unstaking all
                (map-set staked-tokens tx-sender (merge staked-info {amount: (- staked-amount amount)}))
            )
            
            ;; Return tokens to user
            (try! (as-contract (ft-transfer? yield-gov-token amount tx-sender tx-sender)))
            
            (ok true)
        )
    )
)

(define-public (authorize-proposer (proposer principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set authorized-proposers proposer true)
        (ok true)
    )
)

(define-public (revoke-proposer (proposer principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set authorized-proposers proposer false)
        (ok true)
    )
)

(define-public (set-governance-parameters (new-threshold uint) (new-delay uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set min-proposal-threshold new-threshold)
        (var-set voting-delay new-delay)
        (ok true)
    )
)

(define-public (toggle-governance (active bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set governance-active active)
        (ok active)
    )
)

;; Initialize contract with initial token supply
(begin
    (try! (ft-mint? yield-gov-token TOTAL-SUPPLY CONTRACT-OWNER))
    (ok true)
)
