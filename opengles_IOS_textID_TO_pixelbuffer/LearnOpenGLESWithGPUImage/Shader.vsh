//
//  ViewController.m
//  LearnOpenGLESWithGPUImage
//
//  Created by loyinglin on 16/5/10.
//  Copyright © 2016年 loyinglin. All rights reserved.
//

//attribute vec4 position;
//attribute vec2 texCoord;
//
//varying vec2 texCoordVarying;
//
//void main()
//{
//    gl_Position = position;
//    texCoordVarying = texCoord;
//}

attribute vec4 position;
attribute vec4 inputTextureCoordinate;
varying   vec2 textureCoordinate;

void main()
{
    gl_Position = position;
    textureCoordinate = inputTextureCoordinate.xy;
}


//// Hardcode the vertex shader for standard filters, but this can be overridden
//NSString *const kHTSGLVertexShaderString = SHADER_STRING(attribute vec4 position; attribute vec4 inputTextureCoordinate;
//
//                                                         varying vec2 textureCoordinate;
//
//                                                         void main() {
//                                                             gl_Position = position;
//                                                             textureCoordinate = inputTextureCoordinate.xy;
//                                                         });

