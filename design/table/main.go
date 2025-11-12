package main

import (
	"fmt"
	"log"
	"math"

	"github.com/yofu/dxf"
	"github.com/yofu/dxf/color"
	"github.com/yofu/dxf/table"
)

// -------------------- Specs & constants --------------------

type Spec struct {
	W, D            float64
	EllipseWidth    float64 // width of inner recess (formerly ellipse)
	EllipseDepth    float64 // depth of inner recess
	DiagDepthY      float64 // front diagonal cut Y
	BackNotchW      float64
	BackNotchDepth  float64
	BackNotchOffset float64
}

// Fillet specification at a polygon vertex
type Fillet struct {
	X, Y, R float64
}

// global tolerances
const (
	tolerance     = 1e-9 // coordinate equality tolerance
	arcSagittaTol = 0.10 // mm; smaller makes smoother arcs
	keyGrid       = 1e-6 // grid for keying points to map (>= tolerance)
)

// -------------------- Geometry types & helpers --------------------

// Pt is a 2D point / vector.
type Pt struct{ X, Y float64 }

// Basic vector ops (immutable)
func (p Pt) Add(v Pt) Pt        { return Pt{p.X + v.X, p.Y + v.Y} }
func (p Pt) Sub(v Pt) Pt        { return Pt{p.X - v.X, p.Y - v.Y} }
func (p Pt) Scale(s float64) Pt { return Pt{p.X * s, p.Y * s} }
func (p Pt) Dot(v Pt) float64   { return p.X*v.X + p.Y*v.Y }
func (p Pt) Cross(v Pt) float64 { return p.X*v.Y - p.Y*v.X }
func (p Pt) Hypot() float64     { return math.Hypot(p.X, p.Y) }

func (p Pt) Normalize() Pt {
	l := p.Hypot()
	if l < tolerance {
		return Pt{}
	}
	return p.Scale(1 / l)
}

// Rotate around origin by rad
func (p Pt) Rotate(rad float64) Pt {
	c, s := math.Cos(rad), math.Sin(rad)
	return Pt{X: p.X*c - p.Y*s, Y: p.X*s + p.Y*c}
}

func nearlyEqual(a, b, tol float64) bool { return math.Abs(a-b) <= tol }
func clamp(x, lo, hi float64) float64 {
	if x < lo {
		return lo
	}
	if x > hi {
		return hi
	}
	return x
}

func angleBetween(u, v Pt) float64 {
	nu, nv := u.Normalize(), v.Normalize()
	d := clamp(nu.Dot(nv), -1, 1)
	return math.Acos(d)
}

// Stable key for point lookup within tolerance (grid snapping).
func keyOf(p Pt) string {
	// snap to keyGrid; use fmt to avoid float drift in string
	return fmt.Sprintf("%.0f/%.0f", math.Round(p.X/keyGrid), math.Round(p.Y/keyGrid))
}

func main() {
	s := Spec{
		W: 1400, D: 850,
		EllipseWidth: 700, EllipseDepth: 210,
		DiagDepthY: 50,
		BackNotchW: 320, BackNotchDepth: 20, BackNotchOffset: 350,
	}

	// 1) sharp outline
	out := buildOutlineSharp(s)

	// 2) apply fillets
	out = applyFillets(out, []Fillet{
		{X: s.W, Y: s.DiagDepthY, R: 100}, // front-right
		{X: 0, Y: s.DiagDepthY, R: 100},   // front-left
		{X: s.W, Y: s.D, R: 20},           // rear-right
		{X: 0, Y: s.D, R: 20},             // rear-left

		// Recess as sharp 3 points -> fillet them
		{X: s.W/2 + s.EllipseWidth/2, Y: 0, R: 100},
		{X: s.W / 2, Y: s.EllipseDepth, R: 600},
		{X: s.W/2 - s.EllipseWidth/2, Y: 0, R: 100},

		// rear notches (left)
		{X: s.BackNotchOffset - s.BackNotchW/2, Y: s.D, R: 10},
		{X: s.BackNotchOffset - s.BackNotchW/2, Y: s.D - s.BackNotchDepth, R: 8},
		{X: s.BackNotchOffset + s.BackNotchW/2, Y: s.D - s.BackNotchDepth, R: 8},
		{X: s.BackNotchOffset + s.BackNotchW/2, Y: s.D, R: 10},

		// rear notches (right)
		{X: s.W - s.BackNotchOffset - s.BackNotchW/2, Y: s.D, R: 10},
		{X: s.W - s.BackNotchOffset - s.BackNotchW/2, Y: s.D - s.BackNotchDepth, R: 8},
		{X: s.W - s.BackNotchOffset + s.BackNotchW/2, Y: s.D - s.BackNotchDepth, R: 8},
		{X: s.W - s.BackNotchOffset + s.BackNotchW/2, Y: s.D, R: 10},
	}, arcSagittaTol)

	// 3) simplify collinear
	out = simplifyCollinear(out, tolerance)

	// 4) write DXF LWPOLYLINE (closed)
	verts := make([][]float64, 0, len(out))
	for _, p := range out {
		verts = append(verts, []float64{p.X, p.Y})
	}

	d := dxf.NewDrawing()
	if _, err := d.AddLayer("CUT", color.Red, table.LT_CONTINUOUS, true); err != nil {
		log.Fatal(err)
	}
	if _, err := d.LwPolyline(true, verts...); err != nil {
		log.Fatal(err)
	}
	if err := d.SaveAs("tabletop_emarf.dxf"); err != nil {
		log.Fatal(err)
	}
}

// -------------------- Outline (sharp) --------------------

// Build the sharp (pre-fillet) polygon.
// Replaces ellipse recess with three sharp vertices (to be filleted later).
func buildOutlineSharp(s Spec) []Pt {
	n1c := s.BackNotchOffset
	n2c := s.W - s.BackNotchOffset
	nHalf := s.BackNotchW / 2
	nd := s.BackNotchDepth

	return []Pt{
		// start at rear-left corner, clockwise
		{0, s.D},

		// left rear notch
		{n1c - nHalf, s.D},
		{n1c - nHalf, s.D - nd},
		{n1c + nHalf, s.D - nd},
		{n1c + nHalf, s.D},

		// right rear notch
		{n2c - nHalf, s.D},
		{n2c - nHalf, s.D - nd},
		{n2c + nHalf, s.D - nd},
		{n2c + nHalf, s.D},

		// rear-right outer corner
		{s.W, s.D},

		// front-right diagonal vertex (to be filleted)
		{s.W, s.DiagDepthY},

		// inner recess (3 sharp points, to be filleted)
		{s.W/2 + s.EllipseWidth/2, 0},
		{s.W / 2, s.EllipseDepth},
		{s.W/2 - s.EllipseWidth/2, 0},

		// front-left diagonal vertex (to be filleted)
		{0, s.DiagDepthY},

		// loop closes back to {0, s.D}
	}
}

// -------------------- Fillet application --------------------

// applyFillets replaces specified polygon vertices with circular arcs.
// in: closed polygon (CW/CCW, no duplicate end required)
// fillets: (X,Y)->R list; matched by keyOf(Pt{X,Y})
// sagitta: max sagitta for arc tessellation (smaller -> more segments)
func applyFillets(in []Pt, fillets []Fillet, sagitta float64) []Pt {
	if len(in) == 0 || len(fillets) == 0 {
		return in
	}

	// ---- localized helpers (kept private to this function) ----

	// arc tessellation between two tangency points around center
	tessArc := func(center, t1, t2 Pt, r, theta, s float64) []Pt {
		// no arc (too small) -> return just tangency points
		if theta < tolerance {
			return []Pt{t1, t2}
		}
		// segment angle from sagitta: s = R - R*cos(d/2) => d = 2*acos((R-s)/R)
		seg := 2 * math.Acos(clamp((r-s)/r, -1, 1))
		if seg < tolerance {
			return []Pt{t1, t2}
		}
		num := max(int(math.Ceil(theta/seg)), 1)
		step := theta / float64(num)

		// orientation: sign by cross(center->t1, center->t2)
		v1, v2 := t1.Sub(center), t2.Sub(center)
		if v1.Cross(v2) < 0 {
			step = -step
		}

		out := make([]Pt, 0, num+1)
		out = append(out, t1)

		curr := v1
		cs, sn := math.Cos(step), math.Sin(step)
		for range num - 1 {
			curr = Pt{X: curr.X*cs - curr.Y*sn, Y: curr.X*sn + curr.Y*cs}
			out = append(out, center.Add(curr))
		}
		out = append(out, t2)
		return out
	}

	// try to fillet one corner; returns (points, ok)
	filletCorner := func(prev, curr, next Pt, r, sag float64) ([]Pt, bool) {
		if r <= tolerance {
			return nil, false
		}
		// edge vectors (pointing into the corner)
		v1, v2 := prev.Sub(curr), next.Sub(curr)
		l1, l2 := v1.Hypot(), v2.Hypot()
		if l1 < tolerance || l2 < tolerance {
			return nil, false
		}
		u1, u2 := v1.Normalize(), v2.Normalize()
		theta := angleBetween(u1, u2)
		// skip 0 or 180 degrees
		if nearlyEqual(theta, 0, 1e-12) || nearlyEqual(theta, math.Pi, 1e-12) {
			return nil, false
		}

		half := theta / 2
		tanHalf := math.Tan(half)
		if math.Abs(tanHalf) < tolerance {
			return nil, false
		}

		// trim length along each edge from the corner to tangency
		trim := math.Min(r/tanHalf, math.Min(l1, l2)) // clamp by edge length

		// actual radius after clamping (safety for very short edges)
		rActual := trim * tanHalf
		if rActual < tolerance {
			return nil, false
		}
		// center along angle bisector from corner
		sinHalf := math.Sin(half)
		if math.Abs(sinHalf) < tolerance {
			return nil, false
		}

		uBis := u1.Add(u2)
		if uBis.Hypot() < tolerance {
			return nil, false
		}

		return tessArc(
			curr.Add(uBis.Normalize().Scale(rActual/sinHalf)),
			// tangency points
			curr.Add(u1.Scale(trim)),
			curr.Add(u2.Scale(trim)),
			rActual,
			// interior arc sweep = pi - theta  (0..pi)
			math.Pi-theta,
			sag), true
	}

	// ---- main loop ----

	// build radius map for O(1) lookup
	rmap := make(map[string]float64, len(fillets))
	for _, f := range fillets {
		rmap[keyOf(Pt{f.X, f.Y})] = f.R
	}
	n := len(in)
	out := make([]Pt, 0, n*2)
	for i := range n {
		curr := in[i]
		if r, ok := rmap[keyOf(curr)]; ok && r > tolerance {
			prev, next := in[(i+n-1)%n], in[(i+1)%n]
			if pts, ok := filletCorner(prev, curr, next, r, sagitta); ok {
				out = append(out, pts...)
				continue
			}
		}
		out = append(out, curr)
	}
	return out
}

// -------------------- Collinear simplification --------------------

// simplifyCollinear removes nearly-collinear middle vertices from a closed polygon.
// - Keeps polygon closed without duplicating start/end.
// - Uses area (cross) test with tolerance.
func simplifyCollinear(pts []Pt, tol float64) []Pt {
	n := len(pts)
	if n < 3 {
		return pts
	}

	// If first and last are the same within tol, drop the last
	if nearlyEqual(pts[0].X, pts[n-1].X, tol) &&
		nearlyEqual(pts[0].Y, pts[n-1].Y, tol) {
		pts = pts[:n-1]
		n--
	}
	if n < 3 {
		return pts
	}

	out := make([]Pt, 0, n)
	for i := range n {
		curr := pts[i]
		next := pts[(i+1)%n]
		// If cross is small -> a, b, c are nearly collinear; drop b.
		if math.Abs(curr.Sub(pts[(i+n-1)%n]).
			Cross(next.Sub(curr))) > tol {
			out = append(out, curr)
		}
	}

	// If simplification removed too much and broke shape, fall back
	if len(out) < 3 {
		return pts
	}
	return out
}
