// FSR1 (AMD FidelityFX Super Resolution 1.0) - RCAS sharpening pass
// Adapted for Citra MMJ post-processing (GLES single pass).
// The emulator already upscales internally (3x = 1200x720); this pass applies
// the FSR1 Robust Contrast Adaptive Sharpening stage on top of it, which is
// the final stage of the real FSR1 pipeline. It restores edge clarity lost
// during GPU upscaling on Mali G57 (Helio G100).
//
// sharpness: 0.0 = maximum sharpening, 1.0 = disabled (default 0.87)
//! sharpness = 0.87
//! mag_filter = linear
//! min_filter = linear

// FSR RCAS constants (AMD FidelityFX FSR v1.20210629)
#define FSR_RCAS_LIMIT (0.25 - (1.0 / 16.0))

float fsrRcasLoad(float2 p) {
    return SampleLocation(p).g;
}

void FsrRcasCon(out float4 con, float sharpness) {
    // ARRANGE: maximize X = LDR range, Y = 1/X, Z = sharpening amount
    float x = 1.0 / FSR_RCAS_LIMIT;
    con = float4(x, 1.0, sharpness, 0.0);
}

void FsrRcas(float4 con, out float3 pix) {
    // Algorithm uses minimal 3x3 pixel neighborhood.
    //    b
    //  d e f
    //    h
    float2 tp = GetCoordinates();
    float2 iw = GetInvResolution();
    float2 b = tp + float2(0.0, -iw.y);
    float2 d = tp + float2(-iw.x, 0.0);
    float2 f = tp + float2(iw.x, 0.0);
    float2 h = tp + float2(0.0, iw.y);

    float bLuma = fsrRcasLoad(b);
    float dLuma = fsrRcasLoad(d);
    float eLuma = fsrRcasLoad(tp);
    float fLuma = fsrRcasLoad(f);
    float hLuma = fsrRcasLoad(h);

    // Luma times 2.
    float bL = bLuma * 2.0;
    float dL = dLuma * 2.0;
    float eL = eLuma * 2.0;
    float fL = fLuma * 2.0;
    float hL = hLuma * 2.0;

    // Noise detection.
    float nz = 0.25 * (bL + dL + fL + hL) - eLuma;
    nz = clamp(abs(nz) / max(max(bL, eL), max(max(dL, fL), hL)) , 0.0, 1.0);
    nz = -0.5 * nz + 1.0;

    // Min and max of ring.
    float mn4 = min(min(bLuma, dLuma), min(fLuma, hLuma));
    float mx4 = max(max(bLuma, dLuma), max(fLuma, hLuma));

    // Limiters.
    float hitMin = min(mn4, eLuma) / (mx4 * 4.0);
    float hitMax = (hitMin + 1.0) / (mn4 * 4.0 + 1.0);
    float lobeLuma = max(hitMax, hitMin) * nz * con.z;

    // Resolve the lobe - this is the variable number of taps.
    float3 rgb = Sample().rgb;
    float3 bC = SampleLocation(b).rgb;
    float3 dC = SampleLocation(d).rgb;
    float3 fC = SampleLocation(f).rgb;
    float3 hC = SampleLocation(h).rgb;

    float3 lobe = float3(-lobeLuma, -lobeLuma, -lobeLuma);
    pix = (bC + dC + fC + hC + lobe * rgb) / (1.0 + 4.0 * lobeLuma);
    // A tiny bit of saturationpreservation helps.
    pix = mix(rgb, pix, 0.95);
}

void main() {
    float4 con;
    FsrRcasCon(con, clamp(float(sharpness), 0.0, 1.0));
    float3 pix;
    FsrRcas(con, pix);
    SetOutput(float4(pix, 1.0));
}
