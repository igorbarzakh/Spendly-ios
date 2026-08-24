package statistics

import "errors"

var ErrInvalidRange = errors.New("invalid statistics range")

type MonthlyResult struct {
	TotalMinor int64            `json:"total_minor"`
	ByDay      map[string]int64 `json:"by_day"`
	ByCategory map[string]int64 `json:"by_category"`
}
