-- GwangalliFeatures/Registry: APPEND-ONLY list of feature module names in this folder
-- (docs/features_contract.md §1). Re-read before editing; add your own names only.
-- A missing / failing module is skipped with one warning.
return {
	"Transfer", -- money: 송금 / 송금 요청 / 받은 요청 / 거래내역
	"ATM", -- money: ATM / 은행 창구
	"CashGive", -- money: 현금 주기 (in person)
	"TaxiCall", -- taxi_call: 광안콜택시 전화 (call screen, keypad, destination / map picker)
	"TaxiRide", -- taxi_call: 배차 카드 / 미터기 / 결제 / 영수증 / smooth taxi motion
	"CallCar", -- driving: 차 부르기 (Features.open("callcar") -> GwangalliDrive Api sheet)
}
