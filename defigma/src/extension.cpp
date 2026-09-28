#include <dmsdk/sdk.h>

static dmExtension::Result InitializeDefigmaShape(dmExtension::Params* params)
{
    return dmExtension::RESULT_OK;
}

DM_DECLARE_EXTENSION(DefigmaShape, "DefigmaShape", 0, 0, InitializeDefigmaShape, 0, 0, 0)
