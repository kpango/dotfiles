package main

import (
	"log"
	"math"

	"github.com/yofu/dxf"
	"github.com/yofu/dxf/color"
	"github.com/yofu/dxf/table"
)

type Spec struct {
	W, D            float64
	EllipseWidth    float64 // 楕円えぐりの幅
	EllipseDepth    float64 // 楕円えぐりの深さ
	DiagDepthY      float64 // えぐりを適用するY座標
	BackNotchW      float64
	BackNotchDepth  float64
	BackNotchOffset float64
}

// Pt 構造体にベクトル演算メソッドを追加
type Pt struct{ X, Y float64 }

func (p Pt) Add(v Pt) Pt        { return Pt{X: p.X + v.X, Y: p.Y + v.Y} }
func (p Pt) Sub(v Pt) Pt        { return Pt{X: p.X - v.X, Y: p.Y - v.Y} }
func (p Pt) Scale(s float64) Pt { return Pt{X: p.X * s, Y: p.Y * s} }
func (p Pt) Hypot() float64     { return math.Hypot(p.X, p.Y) }
func (p Pt) Normalize() Pt {
	l := p.Hypot()
	if l < 1e-9 {
		return Pt{}
	}
	return p.Scale(1.0 / l)
}
func (p Pt) Dot(v Pt) float64 { return p.X*v.X + p.Y*v.Y }

// フィレット（角丸め）の指定
type Fillet struct {
	X, Y, R float64
}

// 自動分割の弦高許容（小さいほど滑らか）
const arcSagittaTol = 0.10 // mm
const tolerance = 1e-9     // 座標比較用の許容誤差

func main() {
	s := Spec{
		W: 1400, D: 850,
		EllipseWidth: 700, EllipseDepth: 200,
		DiagDepthY: 50, // Y=50 のラインをえぐる
		BackNotchW: 200, BackNotchDepth: 20, BackNotchOffset: 250,
	}

	d := dxf.NewDrawing()
	if _, err := d.AddLayer("CUT", color.Red, table.LT_CONTINUOUS, true); err != nil {
		log.Fatal(err)
	}

	// 1) “鋭角”のまま全シェイプ生成
	out := buildOutlineSharp(s)

	// 2) ★★★ 角丸め（フィレット）処理の適用 ★★★
	out = applyFillets(out, []Fillet{
		{X: s.W, Y: s.DiagDepthY, R: 100}, // 右前の角
		{X: 0, Y: s.DiagDepthY, R: 100},   // 左前の角
		{X: s.W, Y: s.D, R: 20},           // 右後ろの角
		{X: 0, Y: s.D, R: 20},             // 左後ろの角

		// ★★★ 修正 ★★★
		// 楕円の代わりに、3つの「鋭角」の頂点をフィレットする
		{X: s.W/2 + s.EllipseWidth/2, Y: 0, R: 100}, // (1050, 0)
		{X: s.W / 2, Y: s.EllipseDepth, R: 500},     // (700, 150)
		{X: s.W/2 - s.EllipseWidth/2, Y: 0, R: 100}, // (350, 0)

		// 背面ノッチ
		{X: s.BackNotchOffset - s.BackNotchW/2, Y: s.D, R: 10},
		{X: s.BackNotchOffset - s.BackNotchW/2, Y: s.D - s.BackNotchDepth, R: 8},
		{X: s.BackNotchOffset + s.BackNotchW/2, Y: s.D - s.BackNotchDepth, R: 8},
		{X: s.BackNotchOffset + s.BackNotchW/2, Y: s.D, R: 10},
		{X: s.W - s.BackNotchOffset - s.BackNotchW/2, Y: s.D, R: 10},
		{X: s.W - s.BackNotchOffset - s.BackNotchW/2, Y: s.D - s.BackNotchDepth, R: 8},
		{X: s.W - s.BackNotchOffset + s.BackNotchW/2, Y: s.D - s.BackNotchDepth, R: 8},
		{X: s.W - s.BackNotchOffset + s.BackNotchW/2, Y: s.D, R: 10},
	}, arcSagittaTol)

	// 3) 直線連続点の軽い間引き
	out = simplifyCollinear(out)

	// 4) DXF（閉ループ LWPOLYLINE）
	verts := make([][]float64, 0, len(out))
	for _, p := range out {
		verts = append(verts, []float64{p.X, p.Y})
	}
	if _, err := d.LwPolyline(true, verts...); err != nil {
		log.Fatal(err)
	}
	if err := d.SaveAs("tabletop_emarf.dxf"); err != nil {
		log.Fatal(err)
	}
}

/***-------------------------
 * フィレット処理
 *-------------------------*/
func applyFillets(in []Pt, fillets []Fillet, sagitta float64) []Pt {
	if len(fillets) == 0 {
		return in
	}

	n := len(in)
	out := make([]Pt, 0, n*2) // 容量を多めに見積もる

	// 頂点を順に処理し、フィレット対象の頂点を円弧に置き換える
	for i := range n {
		P_curr := in[i] // 現在の頂点

		// --- ★ 簡素化ロジック ★ ---
		// P_currがフィレット対象か、線形探索でチェック
		var radius float64
		isFillet := false
		for _, f := range fillets {
			if math.Abs(P_curr.X-f.X) < tolerance && math.Abs(P_curr.Y-f.Y) < tolerance {
				radius = f.R
				isFillet = true
				break
			}
		}
		// --- ★ 簡素化ロジック (ここまで) ★ ---

		if !isFillet {
			// フィレット対象でない頂点はそのまま追加
			out = append(out, P_curr)
			continue
		}

		// --- ここからフィレット処理 (幾何学計算) ---
		P_prev := in[(i+n-1)%n]
		P_next := in[(i+1)%n]

		v1 := P_prev.Sub(P_curr) // P_curr -> P_prev
		v2 := P_next.Sub(P_curr) // P_curr -> P_next

		lenV1 := v1.Hypot()
		lenV2 := v2.Hypot()

		if lenV1 < tolerance || lenV2 < tolerance {
			out = append(out, P_curr)
			continue
		}

		uv1 := v1.Normalize()
		uv2 := v2.Normalize()
		dot := uv1.Dot(uv2)

		if dot > 1.0-tolerance || dot < -1.0+tolerance {
			out = append(out, P_curr)
			continue
		}

		theta := math.Acos(dot)
		halfTheta := theta / 2.0

		if math.Abs(math.Tan(halfTheta)) < tolerance {
			out = append(out, P_curr)
			continue
		}
		trimDist := radius / math.Tan(halfTheta)

		// --- 安全性チェック (Rが線分長を超える場合) ---
		trimDist = min(trimDist, lenV1) // min は Go 1.21+ 組み込み
		trimDist = min(trimDist, lenV2)

		R_actual := trimDist * math.Tan(halfTheta)

		if R_actual < tolerance {
			out = append(out, P_curr)
			continue
		}

		// 接点 T1, T2
		T1 := P_curr.Add(uv1.Scale(trimDist))
		T2 := P_curr.Add(uv2.Scale(trimDist))

		if math.Abs(math.Sin(halfTheta)) < tolerance {
			out = append(out, P_curr)
			continue
		}
		distC := R_actual / math.Sin(halfTheta)
		uBisector := uv1.Add(uv2).Normalize() // 角の二等分線ベクトル
		C := P_curr.Add(uBisector.Scale(distC))

		// --- 円弧のテッセレーション（多角形近似） ---
		arcSweepAngle := math.Pi - theta
		segAngleRad := 2.0 * math.Acos(max(-1.0, min(1.0, (R_actual-sagitta)/R_actual))) // max/min は Go 1.21+

		if segAngleRad < tolerance {
			out = append(out, T1, T2)
			continue
		}

		numSeg := max(int(math.Ceil(arcSweepAngle/segAngleRad)), 1)

		deltaAngle := arcSweepAngle / float64(numSeg)

		// 回転方向の決定 (T1 -> T2)
		vecT1C := T1.Sub(C)
		vecT2C := T2.Sub(C)
		crossForRotation := vecT1C.X*vecT2C.Y - vecT1C.Y*vecT2C.X
		if crossForRotation < 0 { // 時計回りの場合
			deltaAngle = -deltaAngle
		}

		cosDelta := math.Cos(deltaAngle)
		sinDelta := math.Sin(deltaAngle)

		out = append(out, T1) // 円弧の開始点

		currVec := T1.Sub(C) // 中心CからT1へのベクトル
		for range numSeg - 1 {
			rotatedVec := Pt{
				X: currVec.X*cosDelta - currVec.Y*sinDelta,
				Y: currVec.X*sinDelta + currVec.Y*cosDelta,
			}
			out = append(out, C.Add(rotatedVec))
			currVec = rotatedVec
		}

		out = append(out, T2) // 円弧の終点
	}

	return out
}

/***-------------------------
 * 外形（R適用前：鋭角）
 * buildRecessedEllipse の呼び出しを削除し、
 * 鋭角の頂点 (3点) に置き換える
 *-------------------------*/
func buildOutlineSharp(s Spec) []Pt {
	n1c := s.BackNotchOffset       // 250
	n2c := s.W - s.BackNotchOffset // 1150
	nHalf := s.BackNotchW / 2      // 100
	notchDepth := s.BackNotchDepth //20
	return []Pt{
		// 1. 背面左上 (0, D) から時計回り
		Pt{0, s.D}, // (0, 850)
		// 2. 左ノッチ
		Pt{n1c - nHalf, s.D},              // (150, 850)
		Pt{n1c - nHalf, s.D - notchDepth}, // (150, 830)
		Pt{n1c + nHalf, s.D - notchDepth}, // (350, 830)
		Pt{n1c + nHalf, s.D},              // (350, 850)
		// 3. 右ノッチ
		Pt{n2c - nHalf, s.D},              // (1050, 850)
		Pt{n2c - nHalf, s.D - notchDepth}, // (1050, 830)
		Pt{n2c + nHalf, s.D - notchDepth}, // (1250, 830)
		Pt{n2c + nHalf, s.D},              // (1250, 850)
		// 4. 背面右上
		Pt{s.W, s.D}, // (1400, 850)
		// 5. 右前の角 (フィレット対象)
		Pt{s.W, s.DiagDepthY}, // (1400, 50)
		// 6. 3つの鋭角の頂点を追加内部の抉り
		Pt{s.W/2 + s.EllipseWidth/2, 0}, // (1050, 0)
		Pt{s.W / 2, s.EllipseDepth},     // (700, 150)
		Pt{s.W/2 - s.EllipseWidth/2, 0}, // (350, 0)
		// 7. 左前の角 (フィレット対象)
		Pt{0, s.DiagDepthY}, // (0, 50)
		// 8. 左側面 (始点 (0,850) は自動で閉じる)
	}
}

func simplifyCollinear(in []Pt) []Pt {
	if len(in) < 3 {
		return in
	}
	out := make([]Pt, 0, len(in))
	out = append(out, in[0])
	for i := 1; i < len(in)-1; i++ {
		a, b, c := in[i-1], in[i], in[i+1]
		abx, aby := b.X-a.X, b.Y-a.Y
		bcx, bcy := c.X-b.X, c.Y-b.Y
		if math.Abs(abx*bcy-aby*bcx) > tolerance {
			out = append(out, b)
		}
	}
	out = append(out, in[len(in)-1])

	// 閉ループの始点と終点の重複を処理
	if len(out) > 1 {
		a := out[len(out)-1]
		b := out[0]
		if math.Abs(a.X-b.X) < tolerance && math.Abs(a.Y-b.Y) < tolerance {
			out = out[:len(out)-1] // 最後の点を削除
		}
	}
	return out
}
