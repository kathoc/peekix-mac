#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct VertexUniforms {
    float2 letterboxScale;
    float zoom;
    float pad0;
    float2 zoomOffset;
    float2 pad1;
};

vertex VertexOut vertexShader(uint vid [[vertex_id]],
                              constant VertexUniforms &u [[buffer(0)]]) {
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
    out.position = float4(positions[vid] * u.letterboxScale, 0.0, 1.0);
    float2 tc = texCoords[vid];
    tc = u.zoomOffset + (tc - 0.5) / u.zoom + 0.5;
    out.texCoord = tc;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float, access::sample> yTex [[texture(0)]],
                               texture2d<float, access::sample> cbcrTex [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float  y  = yTex.sample(s, in.texCoord).r - (16.0 / 255.0);
    float2 cc = cbcrTex.sample(s, in.texCoord).rg - float2(0.5, 0.5);
    float cb = cc.x;
    float cr = cc.y;
    float3 rgb;
    rgb.r = 1.164384 * y                 + 1.792741 * cr;
    rgb.g = 1.164384 * y - 0.213249 * cb - 0.532909 * cr;
    rgb.b = 1.164384 * y + 2.112402 * cb;
    return float4(saturate(rgb), 1.0);
}
