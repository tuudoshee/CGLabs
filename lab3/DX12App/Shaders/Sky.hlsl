
SamplerState gsamPointWrap : register(s0);
SamplerState gsamPointClamp : register(s1);
SamplerState gsamLinearWrap : register(s2);
SamplerState gsamLinearClamp : register(s3);
SamplerState gsamAnisotropicWrap : register(s4);
SamplerState gsamAnisotropicClamp : register(s5);
SamplerComparisonState gsamShadow : register(s6);

TextureCube gCubeMap : register(t0);

// Constant data that varies per object.
cbuffer cbPerObject : register(b0)
{
    float4x4 gWorld;
    float4x4 gTexTransform;
    uint gMaterialIndex;
    uint gObjPad0;
    uint gObjPad1;
    uint gObjPad2;
};

// Constant data that varies per frame.
cbuffer cbPass : register(b1)
{
    float4x4 gView;
    float4x4 gInvView;
    float4x4 gProj;
    float4x4 gInvProj;
    float4x4 gViewProj;
    float4x4 gInvViewProj;
    float3 gEyePosW;
    float cbPerObjectPad1;
    float2 gRenderTargetSize;
    float2 gInvRenderTargetSize;
    float gNearZ;
    float gFarZ;
    float gTotalTime;
    float gDeltaTime;

    //Atmosphere
    float3 gSunDirW;
    float gSunIntensity;

    float3 gBetaRayleigh;
    float gRayleighScaleHeight;

    float3 gBetaMie;
    float gMieScaleHeight;

    float gMieG;
    float gAtmosphereDensity;
    float gExposure;
    float gEnableAtmosphere;
};

static const float PI = 3.14159265f;

struct VertexIn
{
    float3 PosL : POSITION;
    float3 NormalL : NORMAL;
    float2 TexC : TEXCOORD;
};

struct VertexOut
{
    float4 PosH : SV_POSITION;
    float3 DirL : TEXCOORD0; 
};

VertexOut VS(VertexIn vin)
{
    VertexOut vout;

    vout.DirL = vin.PosL;

    // world position of sky vertex (no camera position added!)
    float4 posW = mul(float4(vin.PosL, 1.0f), gWorld);

    // remove translation from view
    float4x4 view = gView;
    view._41 = 0;
    view._42 = 0;
    view._43 = 0;

    // use view(no trans) * proj, NOT gViewProj
    float4 posH = mul(posW, mul(view, gProj));

    // push to far plane (classic skybox trick)
    vout.PosH = posH.xyww;

    return vout;
}


//Phase functions
float PhaseRayleigh(float cosTheta)
{
    // 3/(16*pi) * (1 + cos^2)
    return (3.0f / (16.0f * PI)) * (1.0f + cosTheta * cosTheta);
}

float PhaseHG(float cosTheta, float g)
{
    // Henyey-Greenstein phase
    float g2 = g * g;
    float denom = pow(max(1e-3f, 1.0f + g2 - 2.0f * g * cosTheta), 1.5f);
    return (1.0f / (4.0f * PI)) * ((1.0f - g2) / denom);
}

// Cheap "air mass" approximation: more atmosphere near horizon
float AirMassApprox(float viewY)
{
    float mu = saturate(viewY * 0.5f + 0.5f);
    mu = smoothstep(0.0f, 1.0f, mu);
    return lerp(5.0f, 1.0f, mu);
}

// Procedural sky color (single scattering-ish approximation)
float3 SkyColor(float3 viewDirW)
{
    viewDirW = normalize(viewDirW);
    float3 sunDir = normalize(gSunDirW);

    float cosTheta = dot(viewDirW, sunDir);

    float3 betaR = gBetaRayleigh * gAtmosphereDensity;
    float3 betaM = gBetaMie * gAtmosphereDensity;

    float pr = PhaseRayleigh(cosTheta);
    float pm = PhaseHG(cosTheta, gMieG);

    float airMass = AirMassApprox(viewDirW.y);

    float depthScale = 12000.0f;

    float3 tau = (betaR + betaM) * (airMass * depthScale);
    float3 T = exp(-tau);

    float3 scatter = (betaR * pr + betaM * pm) * gSunIntensity * (1.0f - T);

    float t = saturate(viewDirW.y * 0.5f + 0.5f);

    float daylight = smoothstep(-0.08f, 0.03f, sunDir.y);
    float sunsetFactor = 1.0f - smoothstep(0.02f, 0.35f, sunDir.y);

    float3 zenithDay = float3(0.10f, 0.25f, 0.65f);
    float3 horizonDay = float3(0.60f, 0.70f, 0.90f);

    float3 zenithNight = float3(0.01f, 0.02f, 0.05f);
    float3 horizonNight = float3(0.03f, 0.04f, 0.07f);

    float3 baseDay = lerp(horizonDay, zenithDay, t);
    float3 baseNight = lerp(horizonNight, zenithNight, t);

    float3 baseSky = lerp(baseNight, baseDay, daylight);

    float sunDisk = pow(saturate(cosTheta), 3000.0f);
    float sunGlow = pow(saturate(cosTheta), 150.0f);

    float3 sunDay = float3(1.0f, 0.98f, 0.94f);
    float3 sunSunset = float3(1.0f, 0.45f, 0.25f);
    float3 sunTint = lerp(sunDay, sunSunset, sunsetFactor);

    float3 sun = (sunDisk * 1.5f + sunGlow * 0.3f) * gSunIntensity * daylight * sunTint;
    float3 litScatter = scatter * daylight;

    float3 col = baseSky * 0.65f + litScatter * 0.5f + sun;

    return col * gExposure;
}

float4 PS(VertexOut pin) : SV_Target
{
    // Обычный cubemap-режим можно оставить как был
    if (gEnableAtmosphere < 0.5f)
    {
        return gCubeMap.Sample(gsamLinearWrap, normalize(pin.DirL));
    }

    // Восстанавливаем луч из текущего пикселя экрана, а не из грани куба
    float2 uv = pin.PosH.xy * gInvRenderTargetSize; // 0..1
    float2 ndc;
    ndc.x = uv.x * 2.0f - 1.0f;
    ndc.y = 1.0f - uv.y * 2.0f;

    float4 clipPos = float4(ndc, 1.0f, 1.0f);
    float4 viewPos = mul(clipPos, gInvProj);
    float3 viewDirV = normalize(viewPos.xyz / viewPos.w);

    float3 viewDirW = normalize(mul(viewDirV, (float3x3) gInvView));

    float3 col = SkyColor(viewDirW);

    col = max(col, 0.0f);
    col = col / (1.0f + col);

    return float4(col, 1.0f);
}
