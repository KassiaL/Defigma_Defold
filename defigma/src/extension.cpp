#include <dmsdk/sdk.h>

namespace dmDefigma
{
    void RegisterLuaApi(lua_State* L);
}

static dmExtension::Result InitializeDefigmaShape(dmExtension::Params* params)
{
    dmDefigma::RegisterLuaApi(params->m_L);
    return dmExtension::RESULT_OK;
}

DM_DECLARE_EXTENSION(DefigmaShape, "DefigmaShape", 0, 0, InitializeDefigmaShape, 0, 0, 0)
