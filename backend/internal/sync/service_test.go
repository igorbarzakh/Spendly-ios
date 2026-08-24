package sync

import (
	"errors"
	"testing"
	"time"
)

func TestCursorRoundTripAndTamperRejection(t *testing.T) {
	service := NewService(nil, []byte("01234567890123456789012345678901"))
	cursor := Cursor{UpdatedAt: time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC), ID: "11111111-1111-4111-8111-111111111111"}
	raw, e := service.EncodeCursor(cursor)
	if e != nil {
		t.Fatal(e)
	}
	decoded, e := service.DecodeCursor(raw)
	if e != nil || decoded != cursor {
		t.Fatalf("roundtrip: %+v %v", decoded, e)
	}
	raw = raw[:len(raw)-1] + "x"
	if _, e = service.DecodeCursor(raw); !errors.Is(e, ErrInvalidCursor) {
		t.Fatalf("expected tamper rejection, got %v", e)
	}
}
