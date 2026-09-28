#include <string.h>
#include <memory>

#include <dmsdk/dlib/buffer.h>
#include <dmsdk/dlib/hash.h>
#include <dmsdk/dlib/log.h>
#include <dmsdk/dlib/profile.h>
#include <dmsdk/gameobject/gameobject.h>
#include <dmsdk/gamesys/gui.h>
#include <dmsdk/gui/gui.h>

#include <defigma/shape_geometry.h>

namespace dmDefigma
{
    static const dmhash_t PROPERTY_SHAPE         = dmHashString64("shape");
    static const dmhash_t PROPERTY_CORNER_RADIUS = dmHashString64("corner_radius");
    static const dmhash_t PROPERTY_FILLS         = dmHashString64("fills");
    static const dmhash_t PROPERTY_STROKES       = dmHashString64("strokes");
    static const dmhash_t PROPERTY_STROKE_WIDTH  = dmHashString64("stroke_width");
    static const dmhash_t PROPERTY_STROKE_ALIGN  = dmHashString64("stroke_align");
    static const dmhash_t PROPERTY_EFFECTS       = dmHashString64("effects");
    static const dmhash_t PROPERTY_PATH          = dmHashString64("path");
    static const dmhash_t PROPERTY_CLIP          = dmHashString64("clip");

    typedef std::vector<defigma::ShapeVertex> ShapeVertices;

    struct ShapeNode
    {
        std::shared_ptr<const defigma::ShapeDesc> m_Desc;
        std::shared_ptr<const ShapeVertices>      m_Vertices;
        float                                     m_BuiltWidth;
        float                                     m_BuiltHeight;
    };

    static const char* GetStringProperty(dmGui::HScene scene, dmGui::HNode node, dmhash_t key)
    {
        dmGui::CustomProperty property;
        if (dmGui::GetNodeCustomProperty(scene, node, key, &property) != dmGui::RESULT_OK || property.m_Type != dmGui::CUSTOM_PROPERTY_TYPE_STRING)
            return "";
        return property.m_String;
    }

    static float GetNumberProperty(dmGui::HScene scene, dmGui::HNode node, dmhash_t key)
    {
        dmGui::CustomProperty property;
        if (dmGui::GetNodeCustomProperty(scene, node, key, &property) != dmGui::RESULT_OK || property.m_Type != dmGui::CUSTOM_PROPERTY_TYPE_NUMBER)
            return 0.0f;
        return property.m_Number;
    }

    static dmVMath::Vector4 GetVector4Property(dmGui::HScene scene, dmGui::HNode node, dmhash_t key)
    {
        dmGui::CustomProperty property;
        if (dmGui::GetNodeCustomProperty(scene, node, key, &property) != dmGui::RESULT_OK || property.m_Type != dmGui::CUSTOM_PROPERTY_TYPE_VECTOR4)
            return dmVMath::Vector4(0.0f);
        return property.m_Vector4;
    }

    static void LoadDesc(ShapeNode* shape, dmGui::HScene scene, dmGui::HNode node, const char* node_id)
    {
        std::shared_ptr<defigma::ShapeDesc> desc = std::make_shared<defigma::ShapeDesc>();
        defigma::ResetShapeDesc(*desc);
        desc->kind = defigma::ParseShapeKind(GetStringProperty(scene, node, PROPERTY_SHAPE));
        dmVMath::Vector4 radius = GetVector4Property(scene, node, PROPERTY_CORNER_RADIUS);
        desc->corner_radius[0] = radius.getX();
        desc->corner_radius[1] = radius.getY();
        desc->corner_radius[2] = radius.getZ();
        desc->corner_radius[3] = radius.getW();
        desc->stroke_width = GetNumberProperty(scene, node, PROPERTY_STROKE_WIDTH);
        desc->stroke_align = defigma::ParseStrokeAlign(GetStringProperty(scene, node, PROPERTY_STROKE_ALIGN));
        if (!defigma::ParsePaints(GetStringProperty(scene, node, PROPERTY_FILLS), desc->fills))
            dmLogError("DefigmaShape '%s': invalid fills", node_id);
        if (!defigma::ParsePaints(GetStringProperty(scene, node, PROPERTY_STROKES), desc->strokes))
            dmLogError("DefigmaShape '%s': invalid strokes", node_id);
        if (!defigma::ParseEffects(GetStringProperty(scene, node, PROPERTY_EFFECTS), *desc))
            dmLogError("DefigmaShape '%s': invalid effects", node_id);
        if (!defigma::ParsePath(GetStringProperty(scene, node, PROPERTY_PATH), *desc))
            dmLogError("DefigmaShape '%s': invalid path", node_id);
        if (!defigma::ParseClip(GetStringProperty(scene, node, PROPERTY_CLIP), *desc))
            dmLogError("DefigmaShape '%s': invalid clip", node_id);
        shape->m_Desc = desc;
        shape->m_Vertices.reset();
        shape->m_BuiltWidth = -1.0f;
        shape->m_BuiltHeight = -1.0f;
    }

    static void* GuiCreate(const dmGameSystem::CompGuiNodeContext* ctx, void* context, dmGui::HScene scene, dmGui::HNode node, uint32_t custom_type)
    {
        ShapeNode* shape = new ShapeNode();
        std::shared_ptr<defigma::ShapeDesc> desc = std::make_shared<defigma::ShapeDesc>();
        defigma::ResetShapeDesc(*desc);
        shape->m_Desc = desc;
        shape->m_BuiltWidth = -1.0f;
        shape->m_BuiltHeight = -1.0f;
        return shape;
    }

    static void GuiDestroy(const dmGameSystem::CompGuiNodeContext* ctx, const dmGameSystem::CustomNodeCtx* nodectx)
    {
        delete (ShapeNode*)nodectx->m_NodeData;
    }

    static void* GuiClone(const dmGameSystem::CompGuiNodeContext* ctx, const dmGameSystem::CustomNodeCtx* nodectx)
    {
        return new ShapeNode(*(ShapeNode*)nodectx->m_NodeData);
    }

    static void GuiSetNodeDesc(const dmGameSystem::CompGuiNodeContext* ctx, const dmGameSystem::CustomNodeCtx* nodectx, const dmGuiDDF::NodeDesc* node_desc)
    {
        LoadDesc((ShapeNode*)nodectx->m_NodeData, nodectx->m_Scene, nodectx->m_Node, node_desc->m_Id ? node_desc->m_Id : "");
    }

    static void GuiGetVertices(const dmGameSystem::CustomNodeCtx* nodectx, uint32_t decl_size, dmBuffer::StreamDeclaration* decl, uint32_t struct_size, dmArray<uint8_t>& vertices)
    {
        DM_PROFILE("DefigmaShape");
        if (sizeof(defigma::ShapeVertex) != struct_size)
        {
            dmLogOnceError("DefigmaShape vertex is %u bytes, the gui vertex is %u bytes", (uint32_t)sizeof(defigma::ShapeVertex), struct_size);
            return;
        }
        ShapeNode* shape = (ShapeNode*)nodectx->m_NodeData;
        dmVMath::Vector4 size = dmGui::GetNodeProperty(nodectx->m_Scene, nodectx->m_Node, dmGui::PROPERTY_SIZE);
        float width = size.getX();
        float height = size.getY();
        if (!shape->m_Vertices || width != shape->m_BuiltWidth || height != shape->m_BuiltHeight)
        {
            std::shared_ptr<ShapeVertices> built = std::make_shared<ShapeVertices>();
            defigma::BuildShapeVertices(*shape->m_Desc, width, height, *built);
            shape->m_Vertices = built;
            shape->m_BuiltWidth = width;
            shape->m_BuiltHeight = height;
        }
        uint32_t byte_count = (uint32_t)(shape->m_Vertices->size() * sizeof(defigma::ShapeVertex));
        if (byte_count == 0)
            return;
        vertices.SetCapacity(byte_count);
        vertices.SetSize(byte_count);
        memcpy(vertices.Begin(), &(*shape->m_Vertices)[0], byte_count);
    }

    static void GuiUpdate(const dmGameSystem::CustomNodeCtx* nodectx, float dt)
    {
    }

    static dmGameObject::Result GuiNodeTypeCreate(const dmGameSystem::CompGuiNodeTypeCtx* ctx, dmGameSystem::CompGuiNodeType* type)
    {
        dmGameSystem::CompGuiNodeTypeSetContext(type, 0);
        dmGameSystem::CompGuiNodeTypeSetCreateFn(type, GuiCreate);
        dmGameSystem::CompGuiNodeTypeSetDestroyFn(type, GuiDestroy);
        dmGameSystem::CompGuiNodeTypeSetCloneFn(type, GuiClone);
        dmGameSystem::CompGuiNodeTypeSetUpdateFn(type, GuiUpdate);
        dmGameSystem::CompGuiNodeTypeSetGetVerticesFn(type, GuiGetVertices);
        dmGameSystem::CompGuiNodeTypeSetNodeDescFn(type, GuiSetNodeDesc);
        return dmGameObject::RESULT_OK;
    }

    static dmGameObject::Result GuiNodeTypeDestroy(const dmGameSystem::CompGuiNodeTypeCtx* ctx, dmGameSystem::CompGuiNodeType* type)
    {
        return dmGameObject::RESULT_OK;
    }
}

DM_DECLARE_COMPGUI_NODE_TYPE(ComponentTypeGuiNodeDefigmaShape, "DefigmaShape", dmDefigma::GuiNodeTypeCreate, dmDefigma::GuiNodeTypeDestroy)
