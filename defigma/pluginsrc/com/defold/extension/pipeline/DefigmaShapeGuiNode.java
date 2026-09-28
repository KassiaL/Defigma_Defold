package com.defold.extension.pipeline;

import com.dynamo.bob.pipeline.GuiCustomNode;
import com.dynamo.bob.pipeline.IGuiCustomNode;
import com.dynamo.bob.pipeline.IGuiCustomType;
import com.dynamo.gamesys.proto.Gui.Property.PropertyType;
import com.dynamo.proto.DdfMath.Vector4;

@GuiCustomNode(type = "DefigmaShape")
public class DefigmaShapeGuiNode implements IGuiCustomNode {
    public static void registerProperties(IGuiCustomType type) {
        type.addProperty("shape", "rect", PropertyType.TYPE_STRING, IGuiCustomType.EDIT_TYPE_DEFAULT);
        type.addProperty("corner_radius", Vector4.newBuilder().setX(0).setY(0).setZ(0).setW(0).build(), PropertyType.TYPE_VECTOR4, IGuiCustomType.EDIT_TYPE_DEFAULT);
        type.addProperty("fills", "", PropertyType.TYPE_STRING, IGuiCustomType.EDIT_TYPE_DEFAULT);
        type.addProperty("strokes", "", PropertyType.TYPE_STRING, IGuiCustomType.EDIT_TYPE_DEFAULT);
        type.addProperty("stroke_width", 0.0f, PropertyType.TYPE_NUMBER, IGuiCustomType.EDIT_TYPE_DEFAULT);
        type.addProperty("stroke_align", "inside", PropertyType.TYPE_STRING, IGuiCustomType.EDIT_TYPE_DEFAULT);
        type.addProperty("effects", "", PropertyType.TYPE_STRING, IGuiCustomType.EDIT_TYPE_DEFAULT);
        type.addProperty("path", "", PropertyType.TYPE_STRING, IGuiCustomType.EDIT_TYPE_DEFAULT);
        type.addProperty("clip", "", PropertyType.TYPE_STRING, IGuiCustomType.EDIT_TYPE_DEFAULT);
    }
}
