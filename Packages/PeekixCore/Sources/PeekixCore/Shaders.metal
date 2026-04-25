#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position;
    float2 texCoord;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct LetterboxUniforms {
    float2 scale;
};

vertex VertexOut vertexShader(uint vid [[vertex_id]],
                              constant LetterboxUniforms &u [[buffer(0)]]) {
    // Full-screen quad in clip space, scaled to preserve aspect ratio.
    const float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    const float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    VertexOut out;
    out.position = float4(positions[vid] * u.scale, 0.0, 1.0);
    out.texCoord = texCoords[vid];
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float, access::sample> yTex [[texture(0)]],
                               texture2d<float, access::sample> cbcrTex [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float y = yTex.sample(s, in.texCoord).r;
    float2 cbcr = cbcrTex.sample(s, in.texCoord).rg;

    // BT.601 limited-range YCbCr -> RGB.
    float3 ycbcr = float3(y, cbcr.r, cbcr.g);
    const float3x3 m = float3x3(
        float3(1.164383561,  1.164383561,  1.164383561),
        float3(0.0,         -0.391762290,  2.017232142),
        float3(1.596026785, -0.812967647,  0.0)
    );
    const float3 bias = float3(-0.0729, 0.5316, -1.0856);
    float3 rgb = m * ycbcr + bias;
    return float4(rgb, 1.0);
}
