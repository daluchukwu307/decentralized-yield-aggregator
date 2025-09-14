;; Strategy Optimizer Contract
;; Smart contract that analyzes yield opportunities across protocols and executes 
;; optimal allocation strategies while maintaining risk parameters.

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-INVALID-STRATEGY (err u201))
(define-constant ERR-INSUFFICIENT-FUNDS (err u202))
(define-constant ERR-RISK-TOO-HIGH (err u203))
(define-constant ERR-PROTOCOL-NOT-FOUND (err u204))
(define-constant ERR-ALLOCATION-FAILED (err u205))
(define-constant ERR-REBALANCE-NOT-NEEDED (err u206))
(define-constant MAX-PROTOCOLS u20)
(define-constant MAX-RISK-SCORE u100)
(define-constant MIN-YIELD-THRESHOLD u500) ;; 5%
(define-constant REBALANCE-THRESHOLD u200) ;; 2% deviation triggers rebalance

;; Data Variables
(define-data-var optimization-enabled bool true)
(define-data-var max-risk-tolerance uint u70) ;; 70% max risk
(define-data-var min-yield-target uint u800) ;; 8% target yield
(define-data-var next-protocol-id uint u1)
(define-data-var last-optimization uint u0)
(define-data-var total-allocated uint u0)

;; Data Maps
(define-map protocols uint {
    name: (string-ascii 50),
    address: principal,
    current-yield: uint, ;; basis points
    risk-score: uint, ;; 0-100
    tvl: uint,
    allocation: uint,
    max-allocation: uint,
    active: bool,
    last-updated: uint
})

(define-map yield-history uint {
    protocol-id: uint,
    timestamp: uint,
    yield-rate: uint,
    risk-score: uint
})

(define-map optimization-results uint {
    timestamp: uint,
    total-yield: uint,
    risk-score: uint,
    protocols-count: uint,
    rebalanced: bool
})

(define-map authorized-vaults principal bool)
(define-map protocol-performance uint {
    total-returns: uint,
    total-losses: uint,
    success-rate: uint,
    last-performance-check: uint
})

;; Private Functions

(define-private (calculate-risk-adjusted-yield (protocol-id uint))
    (let (
        (protocol (unwrap! (map-get? protocols protocol-id) u0))
        (yield-rate (get current-yield protocol))
        (risk-score (get risk-score protocol))
    )
        ;; Risk-adjusted yield = yield * (100 - risk) / 100
        (/ (* yield-rate (- u100 risk-score)) u100)
    )
)

(define-private (calculate-optimal-allocation (total-amount uint) (protocol-id uint))
    (let (
        (protocol (unwrap! (map-get? protocols protocol-id) u0))
        (risk-adjusted-yield (calculate-risk-adjusted-yield protocol-id))
        (max-alloc (get max-allocation protocol))
        (current-risk (get risk-score protocol))
    )
        ;; Calculate allocation based on risk-adjusted yield and constraints
        (if (and (get active protocol) (<= current-risk (var-get max-risk-tolerance)))
            (min (/ (* total-amount max-alloc) u10000) ;; Respect max allocation
                 (/ (* total-amount risk-adjusted-yield) u10000)) ;; Yield-based allocation
            u0
        )
    )
)

(define-private (get-total-portfolio-risk)
    (fold calculate-weighted-risk (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0)
)

(define-private (calculate-weighted-risk (protocol-id uint) (acc uint))
    (let (
        (protocol (map-get? protocols protocol-id))
    )
        (match protocol
            protocol-data 
                (let (
                    (allocation (get allocation protocol-data))
                    (risk (get risk-score protocol-data))
                    (total-allocated (var-get total-allocated))
                )
                    (if (and (> total-allocated u0) (get active protocol-data))
                        (+ acc (/ (* allocation risk) total-allocated))
                        acc
                    )
                )
            acc
        )
    )
)

(define-private (should-rebalance)
    (let (
        (current-time block-height)
        (last-opt (var-get last-optimization))
        (time-threshold u144) ;; ~24 hours in blocks
    )
        (or (> (- current-time last-opt) time-threshold)
            (> (get-portfolio-deviation) REBALANCE-THRESHOLD))
    )
)

(define-private (get-portfolio-deviation)
    ;; Calculate deviation from optimal allocation
    (fold calculate-allocation-deviation (list u1 u2 u3 u4 u5) u0)
)

(define-private (calculate-allocation-deviation (protocol-id uint) (acc uint))
    (let (
        (protocol (map-get? protocols protocol-id))
    )
        (match protocol
            protocol-data
                (let (
                    (current-alloc (get allocation protocol-data))
                    (optimal-alloc (calculate-optimal-allocation (var-get total-allocated) protocol-id))
                    (deviation (if (> current-alloc optimal-alloc)
                                   (- current-alloc optimal-alloc)
                                   (- optimal-alloc current-alloc)))
                )
                    (+ acc deviation)
                )
            acc
        )
    )
)

(define-private (is-authorized-vault (vault principal))
    (default-to false (map-get? authorized-vaults vault))
)

(define-private (update-yield-history (protocol-id uint) (yield-rate uint) (risk uint))
    (let (
        (history-id (+ (* protocol-id u1000) block-height))
    )
        (map-set yield-history history-id {
            protocol-id: protocol-id,
            timestamp: block-height,
            yield-rate: yield-rate,
            risk-score: risk
        })
    )
)

;; Read-Only Functions

(define-read-only (get-protocol (protocol-id uint))
    (map-get? protocols protocol-id)
)

(define-read-only (get-risk-metrics)
    {
        total-risk: (get-total-portfolio-risk),
        max-tolerance: (var-get max-risk-tolerance),
        portfolio-deviation: (get-portfolio-deviation),
        rebalance-needed: (should-rebalance)
    }
)

(define-read-only (analyze-opportunities)
    (let (
        (active-protocols (filter-active-protocols (list u1 u2 u3 u4 u5)))
        (best-protocol (get-best-protocol active-protocols))
    )
        {
            best-protocol: best-protocol,
            total-protocols: (len active-protocols),
            avg-yield: (calculate-average-yield active-protocols),
            portfolio-risk: (get-total-portfolio-risk)
        }
    )
)

(define-read-only (get-optimization-recommendation (amount uint))
    (let (
        (protocols (list u1 u2 u3 u4 u5))
    )
        (map calculate-protocol-allocation protocols)
    )
)

(define-read-only (get-protocol-performance (protocol-id uint))
    (map-get? protocol-performance protocol-id)
)

(define-read-only (get-yield-history (protocol-id uint) (limit uint))
    ;; Return recent yield history for a protocol (simplified)
    (map-get? yield-history (+ (* protocol-id u1000) block-height))
)

;; Helper read-only functions
(define-private (filter-active-protocols (protocol-ids (list 5 uint)))
    (filter is-protocol-active protocol-ids)
)

(define-private (is-protocol-active (protocol-id uint))
    (match (map-get? protocols protocol-id)
        protocol-data (get active protocol-data)
        false
    )
)

(define-private (get-best-protocol (protocol-ids (list 5 uint)))
    (fold compare-protocols protocol-ids u0)
)

(define-private (compare-protocols (protocol-id uint) (best-id uint))
    (let (
        (current-yield (calculate-risk-adjusted-yield protocol-id))
        (best-yield (calculate-risk-adjusted-yield best-id))
    )
        (if (> current-yield best-yield) protocol-id best-id)
    )
)

(define-private (calculate-average-yield (protocol-ids (list 5 uint)))
    (/ (fold sum-yields protocol-ids u0) (len protocol-ids))
)

(define-private (sum-yields (protocol-id uint) (acc uint))
    (+ acc (calculate-risk-adjusted-yield protocol-id))
)

(define-private (calculate-protocol-allocation (protocol-id uint))
    {
        protocol-id: protocol-id,
        recommended-allocation: (calculate-optimal-allocation (var-get total-allocated) protocol-id),
        risk-adjusted-yield: (calculate-risk-adjusted-yield protocol-id)
    }
)

;; Public Functions

(define-public (register-protocol (name (string-ascii 50)) (address principal) (yield-rate uint) (risk-score uint) (max-allocation uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (<= risk-score MAX-RISK-SCORE) ERR-RISK-TOO-HIGH)
        (asserts! (<= max-allocation u10000) ERR-INVALID-STRATEGY)
        
        (let (
            (protocol-id (var-get next-protocol-id))
        )
            (asserts! (< protocol-id MAX-PROTOCOLS) ERR-PROTOCOL-NOT-FOUND)
            
            (map-set protocols protocol-id {
                name: name,
                address: address,
                current-yield: yield-rate,
                risk-score: risk-score,
                tvl: u0,
                allocation: u0,
                max-allocation: max-allocation,
                active: true,
                last-updated: block-height
            })
            
            (map-set protocol-performance protocol-id {
                total-returns: u0,
                total-losses: u0,
                success-rate: u10000, ;; Start with 100%
                last-performance-check: block-height
            })
            
            (update-yield-history protocol-id yield-rate risk-score)
            (var-set next-protocol-id (+ protocol-id u1))
            
            (ok protocol-id)
        )
    )
)

(define-public (update-protocol-data (protocol-id uint) (yield-rate uint) (risk-score uint))
    (begin
        (asserts! (is-authorized-vault tx-sender) ERR-UNAUTHORIZED)
        (asserts! (<= risk-score MAX-RISK-SCORE) ERR-RISK-TOO-HIGH)
        
        (let (
            (protocol (unwrap! (map-get? protocols protocol-id) ERR-PROTOCOL-NOT-FOUND))
        )
            (map-set protocols protocol-id (merge protocol {
                current-yield: yield-rate,
                risk-score: risk-score,
                last-updated: block-height
            }))
            
            (update-yield-history protocol-id yield-rate risk-score)
            
            (ok true)
        )
    )
)

(define-public (optimize-allocation (total-amount uint))
    (begin
        (asserts! (is-authorized-vault tx-sender) ERR-UNAUTHORIZED)
        (asserts! (var-get optimization-enabled) ERR-INVALID-STRATEGY)
        
        (let (
            (optimization-id block-height)
            (total-risk (get-total-portfolio-risk))
        )
            (asserts! (<= total-risk (var-get max-risk-tolerance)) ERR-RISK-TOO-HIGH)
            
            ;; Update total allocated amount
            (var-set total-allocated total-amount)
            (var-set last-optimization block-height)
            
            ;; Calculate and store optimization results
            (let (
                (avg-yield (calculate-average-yield (list u1 u2 u3 u4 u5)))
            )
                (map-set optimization-results optimization-id {
                    timestamp: block-height,
                    total-yield: avg-yield,
                    risk-score: total-risk,
                    protocols-count: (var-get next-protocol-id),
                    rebalanced: false
                })
            )
            
            (ok {
                total-risk: total-risk,
                expected-yield: (calculate-average-yield (list u1 u2 u3 u4 u5)),
                protocols-used: (var-get next-protocol-id)
            })
        )
    )
)

(define-public (execute-strategy (protocol-id uint) (amount uint))
    (begin
        (asserts! (is-authorized-vault tx-sender) ERR-UNAUTHORIZED)
        (asserts! (> amount u0) ERR-INSUFFICIENT-FUNDS)
        
        (let (
            (protocol (unwrap! (map-get? protocols protocol-id) ERR-PROTOCOL-NOT-FOUND))
            (optimal-amount (calculate-optimal-allocation amount protocol-id))
        )
            (asserts! (get active protocol) ERR-INVALID-STRATEGY)
            (asserts! (<= amount optimal-amount) ERR-ALLOCATION-FAILED)
            
            ;; Update protocol allocation
            (map-set protocols protocol-id (merge protocol {
                allocation: (+ (get allocation protocol) amount),
                tvl: (+ (get tvl protocol) amount)
            }))
            
            (ok {executed: amount, protocol-id: protocol-id})
        )
    )
)

(define-public (rebalance-portfolio)
    (begin
        (asserts! (is-authorized-vault tx-sender) ERR-UNAUTHORIZED)
        (asserts! (should-rebalance) ERR-REBALANCE-NOT-NEEDED)
        
        (let (
            (rebalance-id block-height)
            (current-deviation (get-portfolio-deviation))
        )
            ;; Mark as rebalanced
            (var-set last-optimization block-height)
            
            ;; Update optimization results
            (map-set optimization-results rebalance-id (merge 
                (default-to 
                    {timestamp: u0, total-yield: u0, risk-score: u0, protocols-count: u0, rebalanced: false}
                    (map-get? optimization-results rebalance-id)
                ) 
                {rebalanced: true}
            ))
            
            (ok {
                rebalanced: true,
                deviation-reduced: current-deviation,
                timestamp: block-height
            })
        )
    )
)

(define-public (set-risk-tolerance (new-tolerance uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (<= new-tolerance MAX-RISK-SCORE) ERR-RISK-TOO-HIGH)
        (var-set max-risk-tolerance new-tolerance)
        (ok new-tolerance)
    )
)

(define-public (set-yield-target (new-target uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set min-yield-target new-target)
        (ok new-target)
    )
)

(define-public (authorize-vault (vault principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set authorized-vaults vault true)
        (ok true)
    )
)

(define-public (revoke-vault (vault principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set authorized-vaults vault false)
        (ok true)
    )
)

(define-public (toggle-optimization (enabled bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set optimization-enabled enabled)
        (ok enabled)
    )
)
