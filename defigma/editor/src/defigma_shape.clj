(ns editor.defigma-shape
  (:require [dynamo.graph :as g]
            [editor.gl.vertex2 :as vtx2]
            [editor.gui :as gui]
            [editor.types :as types])
  (:import [com.sun.jna Function NativeLibrary]
           [javax.vecmath Matrix4d Point3d]))

(set! *warn-on-reflection* true)

(def ^:private floats-per-vertex 10)

(def ^:private shape-icon "icons/32/Icons_40-GUI-Box-node.png")

(def ^:private native-library
  (delay (NativeLibrary/getInstance "DefigmaShape")))

(defn- native-function ^Function [name]
  (.getFunction ^NativeLibrary @native-library ^String name))

(defn- build-vertices ^floats [shape corner-radius fills strokes stroke-width stroke-align effects path clip [width height]]
  (let [[tl tr br bl] corner-radius
        vertex-count (.invokeInt (native-function "DefigmaShape_Build")
                                 (object-array [shape (float tl) (float tr) (float br) (float bl)
                                                fills strokes (float stroke-width) stroke-align
                                                effects path clip (float width) (float height)]))]
    (if (pos? vertex-count)
      (let [out (float-array (* vertex-count floats-per-vertex))]
        (.invoke (native-function "DefigmaShape_CopyVertices") Void (object-array [out]))
        out)
      (float-array 0))))

(defn- pivot-offset [pivot [width height]]
  (let [x (case pivot
            (:pivot-e :pivot-ne :pivot-se) -1.0
            (:pivot-center :pivot-n :pivot-s) -0.5
            0.0)
        y (case pivot
            (:pivot-n :pivot-ne :pivot-nw) -1.0
            (:pivot-center :pivot-e :pivot-w) -0.5
            0.0)]
    [(* x width) (* y height)]))

(defn- vertex-count [renderable]
  (quot (alength ^floats (get-in renderable [:user-data :shape-vertices])) floats-per-vertex))

(defn- put-renderable [vb {:keys [^Matrix4d world-transform user-data]}]
  (let [^floats vertices (:shape-vertices user-data)
        [width height] (:size user-data)
        [offset-x offset-y] (:offset user-data)
        [red green blue alpha] (:color user-data)
        point (Point3d.)
        end (alength vertices)]
    (loop [vb vb
           i 0]
      (if (< i end)
        (do
          (.set point
                (+ (double offset-x) (* (double width) (aget vertices i)))
                (+ (double offset-y) (* (double height) (aget vertices (+ i 1))))
                0.0)
          (.transform world-transform point)
          (recur (gui/uv-color-vtx-put! vb
                                        (.x point) (.y point) (.z point)
                                        (aget vertices (+ i 3)) (aget vertices (+ i 4))
                                        (* (double red) (aget vertices (+ i 5)))
                                        (* (double green) (aget vertices (+ i 6)))
                                        (* (double blue) (aget vertices (+ i 7)))
                                        (* (double alpha) (aget vertices (+ i 8)))
                                        (aget vertices (+ i 9)))
                 (+ i floats-per-vertex)))
        vb))))

(defn- gen-vb [_user-data renderables]
  (let [total (transduce (map vertex-count) + renderables)]
    (when (pos? total)
      (vtx2/flip! (reduce put-renderable (gui/->uv-color-vtx total) renderables)))))

(defn- rect-lines [[offset-x offset-y] [width height]]
  (let [x0 offset-x
        y0 offset-y
        x1 (+ offset-x width)
        y1 (+ offset-y height)]
    [[x0 y0 0.0] [x1 y0 0.0]
     [x1 y0 0.0] [x1 y1 0.0]
     [x1 y1 0.0] [x0 y1 0.0]
     [x0 y1 0.0] [x0 y0 0.0]]))

(g/defnk produce-shape-node-msg [shape-base-node-msg ^:raw shape ^:raw corner-radius ^:raw fills ^:raw strokes ^:raw stroke-width ^:raw stroke-align ^:raw effects ^:raw path ^:raw clip]
  (assoc shape-base-node-msg
         :shape shape
         :corner-radius corner-radius
         :fills fills
         :strokes strokes
         :stroke-width stroke-width
         :stroke-align stroke-align
         :effects effects
         :path path
         :clip clip))

(g/defnode DefigmaShapeNode
  (inherits gui/ShapeNode)

  (property shape g/Str (default "rect")
            (static custom-property {:id "shape" :protobuf-type :type-string})
            (dynamic edit-type (gui/layout-property-edit-type shape {:type g/Str}))
            (dynamic label (g/constantly "Shape"))
            (value (gui/layout-property-getter shape))
            (set (gui/layout-property-setter shape)))
  (property corner-radius types/Vec4 (default [0.0 0.0 0.0 0.0])
            (static custom-property {:id "corner_radius" :protobuf-type :type-vector4})
            (dynamic edit-type (gui/layout-property-edit-type corner-radius {:type types/Vec4 :labels ["TL" "TR" "BR" "BL"]}))
            (dynamic label (g/constantly "Corner Radius"))
            (value (gui/layout-property-getter corner-radius))
            (set (gui/layout-property-setter corner-radius)))
  (property fills g/Str (default "")
            (static custom-property {:id "fills" :protobuf-type :type-string})
            (dynamic edit-type (gui/layout-property-edit-type fills {:type g/Str}))
            (dynamic label (g/constantly "Fills"))
            (value (gui/layout-property-getter fills))
            (set (gui/layout-property-setter fills)))
  (property strokes g/Str (default "")
            (static custom-property {:id "strokes" :protobuf-type :type-string})
            (dynamic edit-type (gui/layout-property-edit-type strokes {:type g/Str}))
            (dynamic label (g/constantly "Strokes"))
            (value (gui/layout-property-getter strokes))
            (set (gui/layout-property-setter strokes)))
  (property stroke-width g/Num (default 0.0)
            (static custom-property {:id "stroke_width" :protobuf-type :type-number})
            (dynamic edit-type (gui/layout-property-edit-type stroke-width {:type g/Num}))
            (dynamic label (g/constantly "Stroke Width"))
            (value (gui/layout-property-getter stroke-width))
            (set (gui/layout-property-setter stroke-width)))
  (property stroke-align g/Str (default "inside")
            (static custom-property {:id "stroke_align" :protobuf-type :type-string})
            (dynamic edit-type (gui/layout-property-edit-type stroke-align {:type g/Str}))
            (dynamic label (g/constantly "Stroke Align"))
            (value (gui/layout-property-getter stroke-align))
            (set (gui/layout-property-setter stroke-align)))
  (property effects g/Str (default "")
            (static custom-property {:id "effects" :protobuf-type :type-string})
            (dynamic edit-type (gui/layout-property-edit-type effects {:type g/Str}))
            (dynamic label (g/constantly "Effects"))
            (value (gui/layout-property-getter effects))
            (set (gui/layout-property-setter effects)))
  (property path g/Str (default "")
            (static custom-property {:id "path" :protobuf-type :type-string})
            (dynamic edit-type (gui/layout-property-edit-type path {:type g/Str}))
            (dynamic label (g/constantly "Path"))
            (value (gui/layout-property-getter path))
            (set (gui/layout-property-setter path)))
  (property clip g/Str (default "")
            (static custom-property {:id "clip" :protobuf-type :type-string})
            (dynamic edit-type (gui/layout-property-edit-type clip {:type g/Str}))
            (dynamic label (g/constantly "Clip"))
            (value (gui/layout-property-getter clip))
            (set (gui/layout-property-setter clip)))

  (display-order (into gui/base-display-order
                       [:manual-size :enabled :visible :material :shape :corner-radius :fills :strokes :stroke-width :stroke-align
                        :effects :path :clip :color :alpha :inherit-alpha :layer :blend-mode :pivot :x-anchor :y-anchor :adjust-mode
                        :clipping :visible-clipper :inverted-clipper]))

  (output node-msg g/Any :cached produce-shape-node-msg)
  (output shape-vertices g/Any :cached
          (g/fnk [shape corner-radius fills strokes stroke-width stroke-align effects path clip size]
            (build-vertices shape corner-radius fills strokes stroke-width stroke-align effects path clip size)))
  (output scene-renderable-user-data g/Any :cached
          (g/fnk [pivot size color+alpha shape-vertices clipping-mode clipping-visible clipping-inverted]
            (let [offset (pivot-offset pivot size)]
              (cond-> {:gen-vb gen-vb
                       :shape-vertices shape-vertices
                       :size size
                       :offset offset
                       :color color+alpha
                       :line-data (rect-lines offset size)
                       :renderable-tags #{:gui-shape}}
                (not= :clipping-mode-none clipping-mode)
                (assoc :clipping {:mode clipping-mode :inverted clipping-inverted :visible clipping-visible}))))))

(defn- register-node-type! [workspace]
  (g/transact
    (concat
      (gui/register-custom-node-type-info workspace
                                          {:node-type DefigmaShapeNode
                                           :display-name "Defigma Shape"
                                           :custom-type-name "DefigmaShape"
                                           :icon shape-icon
                                           :defaults (assoc gui/shape-base-node-defaults :size-mode :size-mode-manual)})
      (gui/register-node-tree-attachment-node-type workspace DefigmaShapeNode))))

(defn load-plugin-defigma-shape [workspace]
  (register-node-type! workspace))

(defn return-plugin []
  (fn [workspace] (load-plugin-defigma-shape workspace)))

(return-plugin)
