;; Bitcoin Staking Pool with Yield Optimization


(use-trait ft-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)
(use-trait nft-trait 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9.nft-trait.nft-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-already-initialized (err u101))
(define-constant err-not-initialized (err u102))
(define-constant err-pool-active (err u103))
(define-constant err-pool-inactive (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant err-insufficient-balance (err u106))
(define-constant err-no-yield-available (err u107))
(define-constant err-minimum-stake (err u108))
(define-constant minimum-stake-amount u1000000) ;; 0.01 BTC in sats


;; Data Variables
(define-data-var total-staked uint u0)
(define-data-var total-yield uint u0)
(define-data-var pool-active bool false)
(define-data-var insurance-active bool false)
(define-data-var yield-rate uint u0)
(define-data-var last-distribution-block uint u0)
(define-data-var insurance-fund-balance uint u0)

;; Data Maps
(define-map staker-balances principal uint)
(define-map staker-rewards principal uint)
(define-map yield-distribution-history uint {
    block: uint,
    amount: uint,
    apy: uint
})

(define-map risk-scores principal uint)
(define-map insurance-coverage principal uint)

;; Private Functions
(define-private (calculate-yield (amount uint) (blocks uint))
    (let
        (
            (rate (var-get yield-rate))
            (time-factor (/ blocks u144)) ;; Approximately daily blocks
            (base-yield (* amount rate))
        )
        (/ (* base-yield time-factor) u10000)
    )
)

(define-private (update-risk-score (staker principal) (amount uint))
    (let
        (
            (current-score (default-to u0 (map-get? risk-scores staker)))
            (stake-factor (/ amount u100000000)) ;; Factor based on stake size
            (new-score (+ current-score stake-factor))
        )
        (map-set risk-scores staker new-score)
        (ok new-score)
    )
)

(define-private (check-yield-availability)
    (let
        (
            (current-block block-height)
            (last-distribution (var-get last-distribution-block))
        )
        (if (>= current-block (+ last-distribution u144))
            (ok true)
            err-no-yield-available
        )
    )
)

;; Public Functions
(define-public (initialize-pool (initial-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (var-get pool-active)) err-already-initialized)
        (var-set pool-active true)
        (var-set yield-rate initial-rate)
        (var-set last-distribution-block block-height)
        (ok true)
    )
)

(define-public (stake (amount uint))
    (begin
        (asserts! (var-get pool-active) err-pool-inactive)
        (asserts! (>= amount minimum-stake-amount) err-minimum-stake)
        
        ;; Transfer tokens from user
        (try! (contract-call? 'SP3DX3H4FEYZJZ586MFBS25ZW3HZDMEW92260R2PR.wrapped-bitcoin transfer 
            amount
            tx-sender
            (as-contract tx-sender)
            none
        ))
        
        ;; Update staker balance
        (let
            (
                (current-balance (default-to u0 (map-get? staker-balances tx-sender)))
                (new-balance (+ current-balance amount))
            )
            (map-set staker-balances tx-sender new-balance)
            (var-set total-staked (+ (var-get total-staked) amount))
            
            ;; Update risk score
            (try! (update-risk-score tx-sender amount))
            
            ;; Set up insurance coverage if active
            (if (var-get insurance-active)
                (map-set insurance-coverage tx-sender amount)
                true
            )
            
            (ok true)
        )
    )
)


(define-public (unstake (amount uint))
    (let
        (
            (current-balance (default-to u0 (map-get? staker-balances tx-sender)))
        )
        (asserts! (var-get pool-active) err-pool-inactive)
        (asserts! (>= current-balance amount) err-insufficient-balance)
        
        ;; Process pending rewards before unstaking
        (try! (claim-rewards))
        
        ;; Transfer tokens back to user
        (try! (as-contract (contract-call? 'SP3DX3H4FEYZJZ586MFBS25ZW3HZDMEW92260R2PR.wrapped-bitcoin transfer
            amount
            (as-contract tx-sender)
            tx-sender
            none
        )))
        
        ;; Update balances
        (map-set staker-balances tx-sender (- current-balance amount))
        (var-set total-staked (- (var-get total-staked) amount))
        
        ;; Update insurance coverage if active
        (if (var-get insurance-active)
            (map-set insurance-coverage tx-sender (- current-balance amount))
            true
        )
        
        (ok true)
    )
)


(define-public (distribute-yield)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (var-get pool-active) err-pool-inactive)
        (try! (check-yield-availability))
        
        (let
            (
                (current-block block-height)
                (blocks-passed (- current-block (var-get last-distribution-block)))
                (total-yield-amount (calculate-yield (var-get total-staked) blocks-passed))
            )
            ;; Update total yield
            (var-set total-yield (+ (var-get total-yield) total-yield-amount))
            (var-set last-distribution-block current-block)
            
            ;; Record distribution history
            (map-set yield-distribution-history current-block {
                block: current-block,
                amount: total-yield-amount,
                apy: (var-get yield-rate)
            })
            
            (ok total-yield-amount)
        )
    )
)

(define-public (claim-rewards)
    (begin
        (asserts! (var-get pool-active) err-pool-inactive)
        
        (let
            (
                (staker-balance (default-to u0 (map-get? staker-balances tx-sender)))
                (current-rewards (default-to u0 (map-get? staker-rewards tx-sender)))
                (blocks-passed (- block-height (var-get last-distribution-block)))
                (new-rewards (calculate-yield staker-balance blocks-passed))
                (total-rewards (+ current-rewards new-rewards))
            )
            (asserts! (> total-rewards u0) err-no-yield-available)
            
            ;; Transfer rewards
            (try! (as-contract (contract-call? 'SP3DX3H4FEYZJZ586MFBS25ZW3HZDMEW92260R2PR.wrapped-bitcoin transfer
                total-rewards
                (as-contract tx-sender)
                tx-sender
                none
            )))
            
            ;; Reset rewards
            (map-set staker-rewards tx-sender u0)
            
            (ok total-rewards)
        )
    )
)

;; Read-only functions
(define-read-only (get-staker-balance (staker principal))
    (ok (default-to u0 (map-get? staker-balances staker)))
)

(define-read-only (get-staker-rewards (staker principal))
    (ok (default-to u0 (map-get? staker-rewards staker)))
)

(define-read-only (get-pool-stats)
    (ok {
        total-staked: (var-get total-staked),
        total-yield: (var-get total-yield),
        current-rate: (var-get yield-rate),
        pool-active: (var-get pool-active),
        insurance-active: (var-get insurance-active),
        insurance-balance: (var-get insurance-fund-balance)
    })
)