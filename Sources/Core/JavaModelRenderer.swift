//
//  JavaModelRenderer.swift
//  Core
//
//  Created by Rahul Malik on 1/4/18.
//

import Foundation

public struct JavaModelRenderer: JavaFileRenderer {
    let rootSchema: SchemaObjectRoot
    let params: GenerationParameters

    init(rootSchema: SchemaObjectRoot, params: GenerationParameters) {
        self.rootSchema = rootSchema
        self.params = params
    }

    func renderBuilder() -> JavaIR.Method {
        return JavaIR.method([.public, .static], "Builder builder()") {[
            "return new AutoValue_\(className).Builder();"
        ]}
    }

    func renderBuilderBuild() -> JavaIR.Method {
        return JavaIR.method([.public, .abstract], "\(self.className) build()") {[]}
    }

    func renderToBuilder() -> JavaIR.Method {
        return JavaIR.method([.abstract], "Builder toBuilder()") {[]}
    }

    func renderBuilderProperties(modifiers: JavaModifier = [.public, .abstract]) -> [JavaIR.Method] {
        let props = self.transitiveProperties.map { param, schemaObj in
            JavaIR.method(modifiers, "Builder set\(param.snakeCaseToCamelCase())(\(self.typeFromSchema(param, schemaObj)) value)") {[]}
        }
        return props
    }

    func renderModelProperties(modifiers: JavaModifier = [.public, .abstract]) -> [JavaIR.Method] {
        return self.transitiveProperties.map { param, schemaObj in
            JavaIR.method(modifiers, "@SerializedName(\"\(param)\") \(self.typeFromSchema(param, schemaObj)) \(param.snakeCaseToPropertyName())()") {[]}
        }
    }

    func renderTypeClassAdapter() -> JavaIR.Method {
        return JavaIR.method([.public, .static], "TypeAdapter<\(className)> jsonAdapter(Gson gson)") {[
            "return new AutoValue_\(className).GsonTypeAdapter(gson);"
        ]}
    }

     func renderRoots() -> [JavaIR.Root] {
        let packages = self.params[.packageName].flatMap {
            [JavaIR.Root.packages(names: [$0])]
        } ?? []

        let imports = [
            JavaIR.Root.imports(names: [
                "com.google.auto.value.AutoValue",
                "com.google.gson.Gson",
                "com.google.gson.annotations.SerializedName",
                "com.google.gson.TypeAdapter",
                "java.util.Date",
                "java.util.Map",
                "java.util.Set",
                "java.util.List",
                "java.lang.annotation.Retention",
                "java.lang.annotation.RetentionPolicy",
                "android.support.annotation.IntDef",
                "android.support.annotation.NonNull",
                "android.support.annotation.Nullable",
                "android.support.annotation.StringDef"
            ])
        ]

        let enumProps = self.properties.flatMap { (param, prop) -> [JavaIR.Enum] in
            switch prop.schema {
            case .enumT(let enumValues):
                return [
                    JavaIR.Enum(
                        name: enumTypeName(propertyName: param, className: self.className),
                        values: enumValues
                    )
                ]
            default: return []
            }
        }

        let adtRoots = self.properties.flatMap { (param, prop) -> [JavaIR.Root] in
            switch prop.schema {
            case .oneOf(types: let possibleTypes):
                let objProps = possibleTypes.map { $0.nullableProperty() }
                return adtRootsForSchema(property: param, schemas: objProps)
            case .array(itemType: .some(let itemType)):
                switch itemType {
                case .oneOf(types: let possibleTypes):
                let objProps = possibleTypes.map { $0.nullableProperty() }
                return adtRootsForSchema(property: param, schemas: objProps)
                default: return []
                }
            case .map(valueType: .some(let additionalProperties)):
                switch additionalProperties {
                case .oneOf(types: let possibleTypes):
                    let objProps = possibleTypes.map { $0.nullableProperty() }
                    return adtRootsForSchema(property: param, schemas: objProps)
                default: return []
                }
            default: return []
            }
        }

        let builderClass = JavaIR.Class(
            annotations: ["AutoValue.Builder"],
            modifiers: [.public, .abstract, .static],
            extends: nil,
            implements: nil,
            name: "Builder",
            methods: self.renderBuilderProperties() + [
                self.renderBuilderBuild()
            ],
            enums: [],
            innerClasses: [],
            properties: []
        )

        let modelClass = JavaIR.Root.classDecl(
            aClass: JavaIR.Class(
                annotations: ["AutoValue"],
                modifiers: [.public, .abstract],
                extends: nil,
                implements: nil,
                name: self.className,
                methods: self.renderModelProperties() + [
                    self.renderBuilder(),
                    self.renderToBuilder(),
                    self.renderTypeClassAdapter()
                ],
                enums: enumProps,
                innerClasses: [
                    builderClass
                ],
                properties: []
            )
        )

        let roots: [JavaIR.Root] =
            packages +
            imports +
            adtRoots +
            [ modelClass ]

        return roots
    }
}
