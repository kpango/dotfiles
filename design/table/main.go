package main

import (
	"log"
	"math"

	"github.com/yofu/dxf"
	"github.com/yofu/dxf/color"
	"github.com/yofu/dxf/table"
)

// --- 設計パラメータ ---
const (
	W = 1400.0 // 幅
	D = 900.0  // 奥行

	// 前面角の大R（緩やか）
	RFront = 120.0

	// 前面・楕円えぐり（幅×奥行）
	EllipseWidth = 700.0
	EllipseDepth = 150.0
	EllipseSeg   = 72

	// えぐり両端の斜めカット（左右350, 内側50）
	DiagLenX   = 350.0
	DiagDepthY = 50.0

	// 背面ケーブルノッチ（左右に各1）
	BackNotchW      = 200.0
	BackNotchDepth  = 20.0
	BackNotchOffset = 250.0

	// 前面角フィレット近似分割
	FilletSeg = 18
)

type pt struct{ X, Y float64 }

func main() {
	d := dxf.NewDrawing()

	// CUTレイヤを作成し、カレントに設定（以降のエンティティは自動でCUTになる）
	if _, err := d.AddLayer("CUT", color.Red, table.LT_CONTINUOUS, true); err != nil {
		log.Fatal(err)
	}

	// 外形点列を生成（CCW）
	outline := buildOutline()

	// LWPOLYLINE: 生成時に頂点を渡す（[x, y] のスライス）
	verts := make([][]float64, 0, len(outline))
	for _, p := range outline {
		verts = append(verts, []float64{p.X, p.Y})
	}
	if _, err := d.LwPolyline(true, verts...); err != nil {
		log.Fatal(err)
	}

	if err := d.SaveAs("tabletop_emarf.dxf"); err != nil {
		log.Fatal(err)
	}
}

// CCWで外形を返す（背面左上→背面右→右側面下→前面→左側面上→背面左上）
func buildOutline() []pt {
	var p []pt

	// ---- 背面（上辺）: 左→右、ノッチ2箇所を内側へ ----
	n1c := BackNotchOffset
	n2c := W - BackNotchOffset
	nHalf := BackNotchW / 2

	p = append(p, pt{0, D}) // 背面左上

	// ノッチ1
	p = append(p, pt{n1c - nHalf, D})
	p = append(p, pt{n1c - nHalf, D - BackNotchDepth})
	p = append(p, pt{n1c + nHalf, D - BackNotchDepth})
	p = append(p, pt{n1c + nHalf, D})

	// ノッチ2
	p = append(p, pt{n2c - nHalf, D})
	p = append(p, pt{n2c - nHalf, D - BackNotchDepth})
	p = append(p, pt{n2c + nHalf, D - BackNotchDepth})
	p = append(p, pt{n2c + nHalf, D})

	// 背面右上
	p = append(p, pt{W, D})

	// ---- 右側面：上→下（前面角R開始点へ）----
	p = append(p, pt{W, RFront})

	// ---- 前面右角フィレット（中心 (W-R, R)）----
	// 現在点は (W, R) [θ=0°]。ここから θ: 0 → -90°（減少）に進める。
	cxR, cyR := W-RFront, RFront
	for i := 1; i <= FilletSeg; i++ { // i=1 で重複(θ=0)を避ける
		theta := 0 - (math.Pi/2)*float64(i)/float64(FilletSeg) // 0→-90deg
		x := cxR + RFront*math.Cos(theta)
		y := cyR + RFront*math.Sin(theta)
		p = append(p, pt{x, y}) // 最終到達は (W-R, 0)
	}

	// ---- 右前斜めカット（(W-R,0) から (W-350, 50)）----
	p = append(p, pt{W, DiagDepthY})

	// ---- 前面半楕円えぐり（右端→左端）----
	// 端点: 右端 (xc+a, 0) = (W/2+350, 0) = (1050, 0)
	//       左端 (xc-a, 0) = (350, 0)
	xc := W / 2
	a := EllipseWidth / 2
	b := EllipseDepth
	for i := 0; i <= EllipseSeg; i++ {
		t := float64(i) / float64(EllipseSeg)
		x := xc + a - 2*a*t // 右端→左端
		yy := b * math.Sqrt(maxF(0, 1-((x-xc)*(x-xc))/(a*a)))
		p = append(p, pt{x, yy})
	}

	// ---- 左前斜めカット（(350, 50) へ）----
	p = append(p, pt{0, DiagDepthY})

	// ---- 前面左角フィレット（中心 (R, R)）----
	// 現在点は (R, 0) [θ=-90°]。ここから θ: -90° → -180°（減少）に進める。
	cxL, cyL := RFront, RFront
	for i := 1; i <= FilletSeg; i++ { // i=1 で重複(θ=-90)を避ける
		theta := -math.Pi/2 - (math.Pi/2)*float64(i)/float64(FilletSeg) // -90→-180deg
		x := cxL + RFront*math.Cos(theta)
		y := cyL + RFront*math.Sin(theta)
		p = append(p, pt{x, y}) // 最終到達は (0, R)
	}

	// ---- 左側面：下→上で背面左上に戻る ----
	p = append(p, pt{0, D})

	// 直線連続点の間引き（微少ズレの連続点を削る）
	return simplifyCollinear(p)
}

func maxF(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

// 3点がほぼ同一直線上のとき中点を間引いて軽量化
func simplifyCollinear(in []pt) []pt {
	if len(in) < 3 {
		return in
	}
	out := make([]pt, 0, len(in))
	out = append(out, in[0])
	const eps = 1e-7
	for i := 1; i < len(in)-1; i++ {
		a, b, c := in[i-1], in[i], in[i+1]
		abx, aby := b.X-a.X, b.Y-a.Y
		bcx, bcy := c.X-b.X, c.Y-b.Y
		if math.Abs(abx*bcy-aby*bcx) > eps {
			out = append(out, b)
		}
	}
	out = append(out, in[len(in)-1])
	return out
}
