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