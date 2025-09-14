;; Vault Manager Contract
;; Core vault contract that handles user deposits, withdrawals, and manages 
;; the allocation of funds across different yield farming strategies.

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-VAULT-LOCKED (err u103))
(define-constant ERR-STRATEGY-NOT-FOUND (err u104))
(define-constant ERR-MAX-STRATEGIES-REACHED (err u105))
(define-constant MIN-DEPOSIT u1000000) ;; 1 STX minimum
(define-constant MAX-STRATEGIES u10)
(define-constant MANAGEMENT-FEE u200) ;; 2% (basis points)

;; Data Variables
(define-data-var vault-locked bool false)
(define-data-var total-vault-balance uint u0)
(define-data-var total-shares uint u0)
(define-data-var management-fee uint MANAGEMENT-FEE)
(define-data-var next-strategy-id uint u1)

;; Data Maps
(define-map user-balances principal uint)
(define-map user-shares principal uint)
(define-map strategies uint {
    name: (string-ascii 50),
    address: principal,
    allocation: uint,
    max-allocation: uint,
    active: bool
})
(define-map strategy-balances uint uint)
(define-map authorized-operators principal bool)

;; Private Functions

(define-private (calculate-shares (amount uint))
    (let (
        (current-total-balance (var-get total-vault-balance))
        (current-total-shares (var-get total-shares))
    )
        (if (is-eq current-total-shares u0)
            amount ;; First deposit: 1:1 ratio
            (/ (* amount current-total-shares) current-total-balance)
        )
    )
)

(define-private (calculate-withdrawal-amount (shares uint))
    (let (
        (current-total-balance (var-get total-vault-balance))
        (current-total-shares (var-get total-shares))
    )
        (if (is-eq current-total-shares u0)
            u0
            (/ (* shares current-total-balance) current-total-shares)
        )
    )
)

(define-private (apply-management-fee (amount uint))
    (let (
        (fee (/ (* amount (var-get management-fee)) u10000))
    )
        (- amount fee)
    )
)

(define-private (is-authorized-operator (user principal))
    (default-to false (map-get? authorized-operators user))
)

(define-private (update-user-balance (user principal) (amount uint))
    (map-set user-balances user amount)
)

(define-private (update-user-shares (user principal) (shares uint))
    (map-set user-shares user shares)
)

;; Read-Only Functions

(define-read-only (get-vault-balance)
    (var-get total-vault-balance)
)

(define-read-only (get-user-balance (user principal))
    (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-user-shares (user principal))
    (default-to u0 (map-get? user-shares user))
)

(define-read-only (get-total-shares)
    (var-get total-shares)
)

(define-read-only (get-management-fee)
    (var-get management-fee)
)

(define-read-only (is-vault-locked)
    (var-get vault-locked)
)

(define-read-only (get-strategy (strategy-id uint))
    (map-get? strategies strategy-id)
)

(define-read-only (get-strategy-balance (strategy-id uint))
    (default-to u0 (map-get? strategy-balances strategy-id))
)

(define-read-only (get-user-value (user principal))
    (let (
        (user-shares (get-user-shares user))
        (withdrawal-amount (calculate-withdrawal-amount user-shares))
    )
        (apply-management-fee withdrawal-amount)
    )
)

;; Public Functions

(define-public (deposit (amount uint))
    (begin
        (asserts! (not (var-get vault-locked)) ERR-VAULT-LOCKED)
        (asserts! (>= amount MIN-DEPOSIT) ERR-INVALID-AMOUNT)
        
        (let (
            (shares (calculate-shares amount))
            (current-user-balance (get-user-balance tx-sender))
            (current-user-shares (get-user-shares tx-sender))
        )
            ;; Transfer STX to contract
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            
            ;; Update balances and shares
            (update-user-balance tx-sender (+ current-user-balance amount))
            (update-user-shares tx-sender (+ current-user-shares shares))
            
            ;; Update vault totals
            (var-set total-vault-balance (+ (var-get total-vault-balance) amount))
            (var-set total-shares (+ (var-get total-shares) shares))
            
            (ok {deposited: amount, shares: shares})
        )
    )
)

(define-public (withdraw (shares uint))
    (begin
        (asserts! (not (var-get vault-locked)) ERR-VAULT-LOCKED)
        (asserts! (> shares u0) ERR-INVALID-AMOUNT)
        
        (let (
            (current-user-shares (get-user-shares tx-sender))
            (withdrawal-amount (calculate-withdrawal-amount shares))
            (net-amount (apply-management-fee withdrawal-amount))
            (current-user-balance (get-user-balance tx-sender))
        )
            (asserts! (>= current-user-shares shares) ERR-INSUFFICIENT-BALANCE)
            (asserts! (>= (stx-get-balance (as-contract tx-sender)) net-amount) ERR-INSUFFICIENT-BALANCE)
            
            ;; Transfer STX to user
            (try! (as-contract (stx-transfer? net-amount tx-sender tx-sender)))
            
            ;; Update user balances
            (update-user-shares tx-sender (- current-user-shares shares))
            (update-user-balance tx-sender (- current-user-balance withdrawal-amount))
            
            ;; Update vault totals
            (var-set total-vault-balance (- (var-get total-vault-balance) withdrawal-amount))
            (var-set total-shares (- (var-get total-shares) shares))
            
            (ok {withdrawn: net-amount, shares: shares})
        )
    )
)

(define-public (add-strategy (name (string-ascii 50)) (address principal) (max-allocation uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (<= max-allocation u10000) ERR-INVALID-AMOUNT) ;; Max 100%
        
        (let (
            (strategy-id (var-get next-strategy-id))
        )
            (asserts! (< strategy-id MAX-STRATEGIES) ERR-MAX-STRATEGIES-REACHED)
            
            (map-set strategies strategy-id {
                name: name,
                address: address,
                allocation: u0,
                max-allocation: max-allocation,
                active: true
            })
            
            (map-set strategy-balances strategy-id u0)
            (var-set next-strategy-id (+ strategy-id u1))
            
            (ok strategy-id)
        )
    )
)

(define-public (allocate-funds (strategy-id uint) (amount uint))
    (begin
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-authorized-operator tx-sender)) ERR-UNAUTHORIZED)
        (asserts! (not (var-get vault-locked)) ERR-VAULT-LOCKED)
        
        (let (
            (strategy (unwrap! (map-get? strategies strategy-id) ERR-STRATEGY-NOT-FOUND))
            (current-strategy-balance (get-strategy-balance strategy-id))
            (vault-balance (var-get total-vault-balance))
        )
            (asserts! (get active strategy) ERR-STRATEGY-NOT-FOUND)
            (asserts! (<= amount vault-balance) ERR-INSUFFICIENT-BALANCE)
            
            ;; Check allocation limits
            (let (
                (new-allocation (+ current-strategy-balance amount))
                (max-allowed (/ (* vault-balance (get max-allocation strategy)) u10000))
            )
                (asserts! (<= new-allocation max-allowed) ERR-INVALID-AMOUNT)
                
                ;; Update strategy allocation
                (map-set strategy-balances strategy-id new-allocation)
                
                ;; Transfer funds to strategy contract
                (try! (as-contract (stx-transfer? amount tx-sender (get address strategy))))
                
                (ok {allocated: amount, strategy-id: strategy-id})
            )
        )
    )
)

(define-public (emergency-lock)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set vault-locked true)
        (ok true)
    )
)

(define-public (emergency-unlock)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set vault-locked false)
        (ok true)
    )
)

(define-public (set-management-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (<= new-fee u1000) ERR-INVALID-AMOUNT) ;; Max 10%
        (var-set management-fee new-fee)
        (ok new-fee)
    )
)

(define-public (authorize-operator (operator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set authorized-operators operator true)
        (ok true)
    )
)

(define-public (revoke-operator (operator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set authorized-operators operator false)
        (ok true)
    )
)
