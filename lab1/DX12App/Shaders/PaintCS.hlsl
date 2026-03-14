cbuffer PaintParams : register(b0)
{
    float2 gScreenPx;
    float2 gViewportSize;

    float2 gTexSize;
    float gRootSize;
    float gRadiusPx;

    float gStrength;
    float3 gPad0;

    float4x4 gInvViewProj;
};

RWTexture2D<float> gPaintMask : register(u0);
Texture2D<float4> gDepthTex : register(t0); 

[numthreads(8, 8, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (dtid.x >= (uint) gTexSize.x || dtid.y >= (uint) gTexSize.y)
        return;

    int2 mousePx = int2(gScreenPx);

    if (mousePx.x < 0 || mousePx.y < 0 ||
        mousePx.x >= (int) gViewportSize.x || mousePx.y >= (int) gViewportSize.y)
        return;

    float depth = gDepthTex.Load(int3(mousePx, 0)).a;

    if (depth <= 0.0f || depth >= 1.0f)
        return;

    float2 ndc;
    ndc.x = ((gScreenPx.x + 0.5f) / gViewportSize.x) * 2.0f - 1.0f;
    ndc.y = 1.0f - ((gScreenPx.y + 0.5f) / gViewportSize.y) * 2.0f;

    float4 clipPos = float4(ndc, depth, 1.0f);
    float4 worldPos = mul(clipPos, gInvViewProj);
    worldPos.xyz /= worldPos.w;

    float2 uv = (float2(dtid.xy) + 0.5f) / gTexSize;
    float2 worldXZ = (uv - 0.5f) * gRootSize;

    float dist = distance(worldXZ, worldPos.xz);
    if (dist > gRadiusPx)
        return;

    float falloff = 1.0f - smoothstep(0.0f, gRadiusPx, dist);

    float oldValue = gPaintMask[dtid.xy];
    float newValue = clamp(oldValue + gStrength * falloff, -1.0f, 1.0f);
    gPaintMask[dtid.xy] = newValue;
}
