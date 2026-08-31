package prep

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// --- Source format (their vendor) ---
type SrcOrder struct {
	ID     string         `json:"order_id"`
	Buyer  SrcBuyer       `json:"buyer"`
	Items  []SrcItem      `json:"line_items"`
	Meta   map[string]any `json:"metadata"`
	Placed string         `json:"placed_at"` // RFC3339 string
}
type SrcBuyer struct {
	First string `json:"first_name"`
	Last  string `json:"last_name"`
	Email string `json:"email_address"`
}
type SrcItem struct {
	SKU   string `json:"sku"`
	Qty   int    `json:"quantity"`
	Cents int64  `json:"unit_price_cents"`
}

// --- Target format (our system) ---
type DstOrder struct {
	ExternalID   string    `json:"external_id"`
	CustomerName string    `json:"customer_name"`
	Email        string    `json:"email"`
	TotalCents   int64     `json:"total_cents"`
	Lines        []DstLine `json:"lines"`
	PlacedAt     time.Time `json:"placed_at"`
	Source       string    `json:"source"`
}
type DstLine struct {
	SKU         string `json:"sku"`
	Quantity    int    `json:"quantity"`
	AmountCents int64  `json:"amount_cents"`
}

// MapOrder converts one vendor order into our shape, collecting every problem
// instead of bailing on the first one — integrations fail in batches.
func MapOrder(raw []byte, source string) (DstOrder, error) {
	var s SrcOrder
	dec := json.NewDecoder(strings.NewReader(string(raw)))
	dec.DisallowUnknownFields() // opt-in strictness; drop it if the vendor adds fields freely
	if err := dec.Decode(&s); err != nil {
		return DstOrder{}, fmt.Errorf("decode source order: %w", err)
	}

	var problems []string
	if s.ID == "" {
		problems = append(problems, "missing order_id")
	}
	if s.Buyer.Email == "" {
		problems = append(problems, "missing email_address")
	}

	placed, err := time.Parse(time.RFC3339, s.Placed)
	if err != nil {
		problems = append(problems, fmt.Sprintf("bad placed_at %q", s.Placed))
	}

	d := DstOrder{
		ExternalID:   s.ID,
		CustomerName: strings.TrimSpace(s.Buyer.First + " " + s.Buyer.Last),
		Email:        strings.ToLower(strings.TrimSpace(s.Buyer.Email)),
		PlacedAt:     placed.UTC(),
		Source:       source,
		Lines:        make([]DstLine, 0, len(s.Items)),
	}
	for i, it := range s.Items {
		if it.Qty <= 0 {
			problems = append(problems, fmt.Sprintf("line %d: quantity %d", i, it.Qty))
			continue
		}
		amt := it.Cents * int64(it.Qty) // integer cents; never float money
		d.Lines = append(d.Lines, DstLine{SKU: it.SKU, Quantity: it.Qty, AmountCents: amt})
		d.TotalCents += amt
	}
	if len(problems) > 0 {
		return d, fmt.Errorf("order %s: %s", s.ID, strings.Join(problems, "; "))
	}
	return d, nil
}
