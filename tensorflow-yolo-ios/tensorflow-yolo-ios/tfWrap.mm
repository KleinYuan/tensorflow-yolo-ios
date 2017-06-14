//
//    The MIT License (MIT)
//
//    Copyright (c) 2016 ID Labs L.L.C.
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.
//

#import "tfWrap.h"
#import "tensorflow_utils.h"
#import <CoreImage/CoreImage.h>



@interface tfWrap()
{
    std::string input_layer_name;
    std::string output_layer_name;
    
    float input_mean;
    float input_std;

    std::unique_ptr<tensorflow::Session> tf_session;
    std::unique_ptr<tensorflow::MemmappedEnv> tf_memmapped_env;
    std::vector<std::string> labels;
    
    dispatch_queue_t tfQueue;

}
@end

@implementation tfWrap

- (void) loadModel:(NSString*)graphFileName labels:(NSString*)labelsFileName memMapped:(bool)map optEnv:(bool)opt {
    
    [self createQueue];
    
    dispatch_sync(tfQueue,^{
        NSString* model_file_name;
        NSString* model_file_type;
        
        NSArray* strArr = [graphFileName componentsSeparatedByString:@"."];
        
        if (strArr.count>0) {
            model_file_name = strArr[0];
            
            if (strArr.count>1) {
                model_file_type = strArr[1];
            } else {
                model_file_type = @"pb";
            }
            
            tensorflow::Status load_status;
            
            if (map) {
                LOG(INFO)<< "Loading model with memory mapped";
                load_status = LoadMemoryMappedModel(
                                                    model_file_name, model_file_type, &tf_session, &tf_memmapped_env, opt);
                LOG(INFO)<< "Loaded model with memory mapped";
            } else {
                LOG(INFO)<< "Loading model with memory unmapped";
                load_status = LoadModel(model_file_name, model_file_type, &tf_session);
                LOG(INFO)<< "Loaded model with memory unmapped";
            }
            if (!load_status.ok()) {
                LOG(FATAL) << "Couldn't load model: " << load_status;
            }
            
        }
        
        NSString* labels_file_name;
        NSString* labels_file_type;
        
        strArr = [labelsFileName componentsSeparatedByString:@"."];
        if (strArr.count>0) {
            labels_file_name = strArr[0];
            
            if (strArr.count>1) {
                labels_file_type = strArr[1];
            } else {
                labels_file_type = @"txt";
            }
            
            tensorflow::Status labels_status =
            LoadLabels(labels_file_name, labels_file_type, &labels);
            if (!labels_status.ok()) {
                LOG(FATAL) << "Couldn't load labels: " << labels_status;
            }
            
        }
        
        //default values
        input_mean = 128.0f;
        input_std = 128.0f;
        input_layer_name = "input";
        output_layer_name = "output";
    });
}

- (void) loadModel:(NSString*)graphFileName labels:(NSString*)labelsFileName memMapped:(bool)map {
    
    [self loadModel:graphFileName labels:labelsFileName memMapped:map optEnv:false];
}

- (void) loadModel:(NSString*)graphFileName labels:(NSString*)labelsFileName {
    [self loadModel:graphFileName labels:labelsFileName memMapped:false optEnv:false];
}

-(void) clean {
    [self createQueue];
    
    dispatch_sync(tfQueue, ^{
        CleanSession(&tf_session);
        labels.clear();
    });
}

-(void)setInputLayer:(NSString *)inLayer outputLayer:(NSString *)outLayer {
    
    [self createQueue];
    
    dispatch_sync(tfQueue, ^{
        input_layer_name = [inLayer UTF8String];
        output_layer_name = [outLayer UTF8String];
    });
}

-(void)setInputMean:(float)mean std:(float)std {
    
    [self createQueue];
    
    dispatch_sync(tfQueue, ^{
        input_mean = mean; input_std = std;
    });
}

-(NSArray*) getLabels {
    
    //LOG(INFO) << "Labels count " << labels.size();
    NSMutableArray* arr = [NSMutableArray array];
    for (int index = 0; index < labels.size(); index += 1) {
        std::string label = labels[index];
        NSString *labelObject = [NSString stringWithUTF8String:label.c_str()];
        
        [arr addObject:labelObject];
    }
    
    return arr;
}

- (NSArray*)runOnFrame:(CVPixelBufferRef)pixelBuffer {
    assert(pixelBuffer != NULL);
    
    [self createQueue];
    
    __block NSArray* output;
    
    dispatch_sync(tfQueue, ^{
    
        const int sourceRowBytes = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
        const int image_width = (int)CVPixelBufferGetWidth(pixelBuffer);
        const int fullHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
        
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        
        unsigned char *sourceBaseAddr =
        (unsigned char *)(CVPixelBufferGetBaseAddress(pixelBuffer));
        int image_height;
        unsigned char *sourceStartAddr;
        if (fullHeight <= image_width) {
            image_height = fullHeight;
            sourceStartAddr = sourceBaseAddr;
        } else {
            image_height = image_width;
            const int marginY = ((fullHeight - image_width) / 2);
            sourceStartAddr = (sourceBaseAddr + (marginY * sourceRowBytes));
        }
        
        const int image_channels = 4;
        const int wanted_input_channels = 3;
        assert(image_channels >= wanted_input_channels);
        
        int wanted_input_width; int wanted_input_height;
        
        wanted_input_width = image_width;
        wanted_input_height = image_height;
        
        tensorflow::Tensor image_tensor(tensorflow::DT_FLOAT,
                                        tensorflow::TensorShape({1, wanted_input_height, wanted_input_width, wanted_input_channels}));
        
        auto image_tensor_mapped = image_tensor.tensor<float, 4>();
        tensorflow::uint8 *inn = sourceStartAddr;
        float *outt = image_tensor_mapped.data();
        
        for (int y = 0; y < wanted_input_height; ++y) {
            float *out_row = outt + (y * wanted_input_width * wanted_input_channels);
            for (int x = 0; x < wanted_input_width; ++x) {
                tensorflow::uint8 *in_pixel =
                inn + (y * image_width * image_channels) + (x * image_channels);
                float *out_pixel = out_row + (x * wanted_input_channels);
                for (int c = 0; c < wanted_input_channels; ++c) {
                    out_pixel[c] = (in_pixel[wanted_input_channels-c-1] - input_mean) / input_std;
                }
            }
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        
        if (tf_session.get()) {
            
            std::vector<tensorflow::Tensor> outputs;
            tensorflow::Status run_status = tf_session->Run({{input_layer_name, image_tensor}}, {output_layer_name}, {}, &outputs);
            if (!run_status.ok()) {
                LOG(ERROR) << "Running model failed:" << run_status;
            } else {
                
                //LOG(INFO)<< "Run duration: "<< -[startTime timeIntervalSinceNow];
                
                tensorflow::Tensor *outputTensor = &outputs[0];
                /*
                LOG(INFO)<< "Tensor dim[0] " << outputTensor->shape().dim_size(0);
                LOG(INFO)<< "Tensor dim[1] " << outputTensor->shape().dim_size(1);//1470 = 7x7x(2*5+20)
                */
                
                auto values = outputTensor->flat<float>();
                //LOG(INFO)<<values;
                //LOG(INFO)<< "Output size " << values.size();
                
                NSMutableArray* arr = [NSMutableArray array];
                
                for (int index = 0; index < values.size(); index += 1) {
                    const float v = values(index);
                    [arr addObject:[NSNumber numberWithDouble:v]];
                }
                
                output = arr;
            }
        }
        
    });
    
    return output;
}

-(void) createQueue {
    if (tfQueue==nil) {
        tfQueue = dispatch_queue_create("tfQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, 0));
    }
}


@end


