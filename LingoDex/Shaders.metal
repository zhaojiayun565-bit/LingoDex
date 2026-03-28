#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>

using namespace metal;

/// Pixelates, desaturates, and fades the layer so the app background can show through.
/// `progress` in 0...1.
[[ stitchable ]] half4 pixelateDissolve(float2 position, SwiftUI::Layer layer, float progress) {
    float p = clamp(progress, 0.0f, 1.0f);
    float cell = max(1.0f, mix(1.0f, 56.0f, p * p));
    float2 coord = floor(position / cell) * cell + cell * 0.5f;
    half4 c = layer.sample(coord);
    float gray = dot(float3(c.rgb), float3(0.299f, 0.587f, 0.114f));
    half3 grayH = half3(gray);
    float desat = smoothstep(0.35f, 1.0f, p);
    half3 rgb = mix(c.rgb, grayH, half(desat));
    float alphaFade = smoothstep(0.55f, 1.0f, p);
    half a = c.a * half(1.0f - alphaFade);
    return half4(rgb, a);
}
