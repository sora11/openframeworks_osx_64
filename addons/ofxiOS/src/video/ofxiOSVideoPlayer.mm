#import "ofxiOSVideoPlayer.h"
//#import "ofxiOSExtras.h"
#import "AVFoundationVideoPlayer.h"

#ifdef __IPHONE_5_0
CVOpenGLESTextureCacheRef _videoTextureCache = NULL;
CVOpenGLESTextureRef _videoTextureRef = NULL;
#endif

ofxiOSVideoPlayer::ofxiOSVideoPlayer() {
	videoPlayer = NULL;
	pixelsRGB = NULL;
	pixelsRGBA = NULL;
    internalGLFormat = GL_RGB;
	internalPixelFormat = OF_PIXELS_RGB;
	
    bFrameNew = false;
    bResetPixels = false;
    bResetTexture = false;
    bUpdatePixels = false;
    bUpdatePixelsToRgb = false;
    bUpdateTexture = false;
    bTextureHack = false;
    bTextureCacheSupported = false;
#ifdef __IPHONE_5_0    
    bTextureCacheSupported = (CVOpenGLESTextureCacheCreate != NULL);
#endif    
}

//----------------------------------------
ofxiOSVideoPlayer::~ofxiOSVideoPlayer() {
	close();
}

//----------------------------------------
bool ofxiOSVideoPlayer::loadMovie(string name) {
	
    if(!videoPlayer) {
        videoPlayer = [[AVFoundationVideoPlayer alloc] init];
        [(AVFoundationVideoPlayer *)videoPlayer setWillBeUpdatedExternally:YES];
    }
    
    NSString * videoPath = [NSString stringWithUTF8String:ofToDataPath(name).c_str()];
    [(AVFoundationVideoPlayer*)videoPlayer loadWithPath:videoPath];
    
    bResetPixels = true;
    bResetTexture = true;
    bUpdatePixels = true;
    bUpdatePixelsToRgb = true;
    bUpdateTexture = true;
    
#ifdef __IPHONE_5_0
    if(bTextureCacheSupported) {
        if(_videoTextureCache == NULL) {
            CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, 
                                                        NULL, 
                                                        ofxiOSGetGLView().context,
                                                        NULL, 
                                                        &_videoTextureCache);
            if(err) {
                NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            }    
        }
    }
#endif
    
    return true;
}

//----------------------------------------
void ofxiOSVideoPlayer::close() {
	if(videoPlayer != NULL) {
		
		if(pixelsRGBA != NULL) {
			free(pixelsRGBA);
			pixelsRGBA = NULL;
		}
        
		if(pixelsRGB != NULL) {
			free(pixelsRGB);
			pixelsRGB = NULL;
		}
        
        if(!bTextureHack) {
            if(videoTexture.bAllocated()) {
                videoTexture.clear();
            }
        }
		
        ((AVFoundationVideoPlayer *)videoPlayer).delegate = nil;
		[(AVFoundationVideoPlayer *)videoPlayer release];
        
#ifdef __IPHONE_5_0
        if(bTextureCacheSupported) {
            if(_videoTextureRef) {
                CFRelease(_videoTextureRef);
                _videoTextureRef = NULL;
            }
            
            if(_videoTextureCache) {
                CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
                CFRelease(_videoTextureCache);
                _videoTextureCache = NULL;
            }
        }
#endif
	}
	videoPlayer = NULL;
    
    bFrameNew = false;
    bResetPixels = false;
    bResetTexture = false;
    bUpdatePixels = false;
    bUpdatePixelsToRgb = false;
    bUpdateTexture = false;
}

//----------------------------------------
bool ofxiOSVideoPlayer::setPixelFormat(ofPixelFormat _internalPixelFormat) {
	if(_internalPixelFormat == OF_PIXELS_RGB) {
		internalPixelFormat = _internalPixelFormat;
		internalGLFormat = GL_RGB;
		return true;		
    } else if(_internalPixelFormat == OF_PIXELS_RGBA) {
		internalPixelFormat = _internalPixelFormat;
		internalGLFormat = GL_RGBA;
		return true;
    } else if(_internalPixelFormat == OF_PIXELS_BGRA) {
		internalPixelFormat = _internalPixelFormat;	
		internalGLFormat = GL_BGRA;
		return true;
    }
	return false;
}


//---------------------------------------------------------------------------
ofPixelFormat ofxiOSVideoPlayer::getPixelFormat(){
	return internalPixelFormat;
}

//----------------------------------------
void ofxiOSVideoPlayer::update() {
    
    bFrameNew = false; // default.
    
    if(!isLoaded()) {
        return;
    }
    
    [(AVFoundationVideoPlayer *)videoPlayer update];
    bFrameNew = [(AVFoundationVideoPlayer *)videoPlayer isNewFrame]; // check for new frame staright after the call to update.
    
    if(bFrameNew) {
        /**
         *  mark pixels to be updated.
         *  pixels are then only updated if the getPixels() method is called,
         *  internally or externally to this class.
         *  this ensures the pixels are updated only once per frame.
         */
        bUpdatePixels = true;
        bUpdatePixelsToRgb = true;
        bUpdateTexture = true;
    }
}

//----------------------------------------
void ofxiOSVideoPlayer::play() {
    if(videoPlayer == NULL) {
        ofLogWarning("ofxiOSVideoPlayer") << "play(): video not loaded";
    }
    
	[(AVFoundationVideoPlayer *)videoPlayer play];
}

//----------------------------------------
void ofxiOSVideoPlayer::stop() {
    if(videoPlayer == NULL) {
        return;
    }
    
    [(AVFoundationVideoPlayer *)videoPlayer pause];
    [(AVFoundationVideoPlayer *)videoPlayer setPosition:0];
}		

//----------------------------------------
bool ofxiOSVideoPlayer::isFrameNew() {
	if(videoPlayer != NULL) {
		return bFrameNew;
	}	
	return false;
}

//----------------------------------------
unsigned char * ofxiOSVideoPlayer::getPixels() {
    
	if(isLoaded())
	{
        if(!bUpdatePixels) { // if pixels have not changed, return the already calculated pixels.
            if(internalGLFormat == GL_RGB) {
                updatePixelsToRGB();
                return pixelsRGB;
            }  else if(internalGLFormat == GL_RGBA || internalGLFormat == GL_BGRA) {
                return pixelsRGBA;
            }
        }
        
		CGImageRef currentFrameRef;
		
		NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
		
		CVImageBufferRef imageBuffer = [(AVFoundationVideoPlayer *)videoPlayer getCurrentFrame]; 
        
		/*Lock the image buffer*/
		CVPixelBufferLockBaseAddress(imageBuffer,0);
		
		/*Get information about the image*/
		uint8_t *baseAddress	= (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer); 
		size_t bytesPerRow		= CVPixelBufferGetBytesPerRow(imageBuffer); 
		size_t width			= CVPixelBufferGetWidth(imageBuffer); 
		size_t height			= CVPixelBufferGetHeight(imageBuffer);  
		
		/*Create a CGImageRef from the CVImageBufferRef*/
		CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB(); 
		CGContextRef newContext = CGBitmapContextCreate(baseAddress, 
                                                        width, 
                                                        height, 
                                                        8, 
                                                        bytesPerRow, 
                                                        colorSpace, 
                                                        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
		CGImageRef newImage	= CGBitmapContextCreateImage(newContext); 
		
		currentFrameRef = CGImageCreateCopy(newImage);		
		
		/*We release some components*/
		CGContextRelease(newContext); 
		CGColorSpaceRelease(colorSpace);
		
		/*We relase the CGImageRef*/
		CGImageRelease(newImage);
		
		/*We unlock the  image buffer*/
		CVPixelBufferUnlockBaseAddress(imageBuffer,0);
		
		if(bResetPixels) {
            
            if(pixelsRGBA != NULL) {
                free(pixelsRGBA);
                pixelsRGBA = NULL;
            }
            
            if(pixelsRGB != NULL) {
                free(pixelsRGB);
                pixelsRGB = NULL;
            }

            pixelsRGBA = (GLubyte *) malloc(width * height * 4);
            pixelsRGB  = (GLubyte *) malloc(width * height * 3);
            
            bResetPixels = false;
		}
		
		[pool drain];
		
        CGContextRef spriteContext;
        spriteContext = CGBitmapContextCreate(pixelsRGBA, 
                                              width, 
                                              height, 
                                              CGImageGetBitsPerComponent(currentFrameRef), 
                                              width * 4, 
                                              CGImageGetColorSpace(currentFrameRef), 
                                              kCGImageAlphaPremultipliedLast);
        
        CGContextDrawImage(spriteContext, 
                           CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), 
                           currentFrameRef);
        
        CGContextRelease(spriteContext);
        
        if(internalGLFormat == GL_RGB) {
            updatePixelsToRGB();
        } else if(internalGLFormat == GL_RGBA || internalGLFormat == GL_BGRA) {
            // pixels are already 4 channel. 
            // return pixelsRaw instead of pixels (further down).
        }
        
        CGImageRelease(currentFrameRef);
		
        bUpdatePixels = false;
        
        if(internalGLFormat == GL_RGB) {
            return pixelsRGB;
        }  else if(internalGLFormat == GL_RGBA || internalGLFormat == GL_BGRA) {
            return pixelsRGBA;
        }
        
        return NULL;
	}
	
	return NULL;
}

void ofxiOSVideoPlayer::updatePixelsToRGB () {
    if(!bUpdatePixelsToRgb) {
        return;
    }
    
    int width = [(AVFoundationVideoPlayer *)videoPlayer getWidth];
    int height = [(AVFoundationVideoPlayer *)videoPlayer getHeight];

    unsigned int *isrc4 = (unsigned int *)pixelsRGBA;
    unsigned int *idst3 = (unsigned int *)pixelsRGB;
    unsigned int *ilast4 = &isrc4[width*height-1];
    while (isrc4 < ilast4){
        *(idst3++) = *(isrc4++);
        idst3 = (unsigned int *) (((unsigned char *) idst3) - 1);
    }
    
    bUpdatePixelsToRgb = false;
}

//----------------------------------------
ofPixelsRef ofxiOSVideoPlayer::getPixelsRef() {
    static ofPixels dummy;
    return dummy;
}

//----------------------------------------
ofTexture * ofxiOSVideoPlayer::getTexture() {
    
    if(!isLoaded()) {
        return &videoTexture;
    }
    
    if(!bUpdateTexture) {
        return &videoTexture;
    }

    CVImageBufferRef imageBuffer = [(AVFoundationVideoPlayer *)videoPlayer getCurrentFrame];
    CVPixelBufferLockBaseAddress(imageBuffer,0); 
    
#ifdef __IPHONE_5_0
    
    BOOL bUseTextureCache = bTextureCacheSupported;
    if(bUseTextureCache) {
        bUseTextureCache = bUseTextureCache && (_videoTextureCache != NULL);
    }
    
    if(bUseTextureCache) {
        /**
         *  video texture cache is available.
         *  this means we don't have to copy any pixels,
         *  and we can reuse the already existing video texture.
         *  this is very fast! :)
         */
        
        if(_videoTextureRef) {
            CFRelease(_videoTextureRef);
            _videoTextureRef = NULL;
        }
        CVOpenGLESTextureCacheFlush(_videoTextureCache, 0); // Periodic texture cache flush every frame
        
        /**
         *  CVOpenGLESTextureCache does this operation for us.
         *  it automatically returns a texture reference which means we don't have to create the texture ourselves.
         *  but we do want to return an ofTexture object...
         *  this creates a slight problem because when we create an ofTexture objects, it also creates a opengl texture for us,
         *  which is unecessary in this case because the texture already exists.
         *  so... the below is somewhat of a hack to reuse an existing texture and give it to a ofTexture object.
         */
        
        bTextureHack = true;
        
        ofTextureData texData;
        texData.tex_w = texData.width = [(AVFoundationVideoPlayer *)videoPlayer getWidth];
        texData.tex_h = texData.height = [(AVFoundationVideoPlayer *)videoPlayer getHeight];
        texData.tex_w = ofNextPow2(texData.tex_w);
        texData.tex_h = ofNextPow2(texData.tex_h);
        texData.tex_t = 1.0f;
        texData.tex_u = 1.0f;
        texData.textureTarget = GL_TEXTURE_2D;
        texData.glTypeInternal = GL_RGBA; // opengl format
        texData.bAllocated = true;
        
        glActiveTexture(GL_TEXTURE0);
        
        /**
         *  create video texture from video image.
         *  inside this function, ios is creating the texture for us.
         *  a video texture reference is returned.
         */
        CVReturn err;
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,     // CFAllocatorRef allocator
                                                           _videoTextureCache,      // CVOpenGLESTextureCacheRef textureCache
                                                           imageBuffer,             // CVImageBufferRef sourceImage
                                                           NULL,                    // CFDictionaryRef textureAttributes
                                                           texData.textureTarget,   // GLenum target
                                                           texData.glTypeInternal,  // GLint internalFormat
                                                           texData.width,           // GLsizei width
                                                           texData.height,          // GLsizei height
                                                           GL_BGRA,                 // GLenum format
                                                           GL_UNSIGNED_BYTE,        // GLenum type
                                                           0,                       // size_t planeIndex
                                                           &_videoTextureRef);      // CVOpenGLESTextureRef *textureOut
        
        /**
         *  get the generated textureID and textureTarget.
         *  configure the texture (this is from inside ofTexture::allocate).
         *  and add give it to an ofTexture object.
         */
        texData.textureID = CVOpenGLESTextureGetName(_videoTextureRef);
        texData.textureTarget = CVOpenGLESTextureGetTarget(_videoTextureRef);
        
        glEnable(texData.textureTarget);
        glBindTexture(texData.textureTarget, (GLuint)texData.textureID);
        glTexParameterf(texData.textureTarget, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(texData.textureTarget, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(texData.textureTarget, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(texData.textureTarget, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
        glDisable(texData.textureTarget);
        
        videoTexture.texData = texData;
        
        if(err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }            
    } else 
#endif            
    {
        /**
         *  no video texture cache.
         *  load texture from pixels.
         *  this method is the slower alternative.
         */
        
        int maxTextureSize = 0;
        glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTextureSize);
        
        if([(AVFoundationVideoPlayer *)videoPlayer getWidth] > maxTextureSize || 
           [(AVFoundationVideoPlayer *)videoPlayer getHeight] > maxTextureSize) {
            ofLogWarning("ofxiOSVideoPlayer") << "getTexture(): "
				<< [(AVFoundationVideoPlayer *)videoPlayer getWidth] << "x" << [(AVFoundationVideoPlayer *)videoPlayer getHeight]
				<< " video image is bigger then max supported texture size " << maxTextureSize;
            return NULL;
        }
        
        bTextureHack = false;
        
        if(bResetTexture) {
            
            if(videoTexture.bAllocated()) {
                videoTexture.clear();
            }
            
            videoTexture.allocate([(AVFoundationVideoPlayer *)videoPlayer getWidth], 
                                  [(AVFoundationVideoPlayer *)videoPlayer getHeight], 
                                  GL_RGBA);
        }
        
        GLint internalGLFormatCopy = internalGLFormat;
        internalGLFormat = GL_RGBA;
        videoTexture.loadData(getPixels(), 
                              [(AVFoundationVideoPlayer *)videoPlayer getWidth], 
                              [(AVFoundationVideoPlayer *)videoPlayer getHeight], 
                              internalGLFormat);
        internalGLFormat = internalGLFormatCopy;
    }
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0); // unlock the image buffer
    
    bUpdateTexture = false;
    
    return &videoTexture;
}

//----------------------------------------
float ofxiOSVideoPlayer::getWidth() {
    if(videoPlayer == NULL) {
        return 0;
    }
    
    return [((AVFoundationVideoPlayer *)videoPlayer) getWidth];
}

//----------------------------------------
float ofxiOSVideoPlayer::getHeight() {
    if(videoPlayer == NULL) {
        return 0;
    }
    
    return [((AVFoundationVideoPlayer *)videoPlayer) getHeight];
}

//----------------------------------------
bool ofxiOSVideoPlayer::isPaused() {
    if(videoPlayer == NULL) {
        return false;
    }
    
    return ![((AVFoundationVideoPlayer *)videoPlayer) isPlaying];
}

//----------------------------------------
bool ofxiOSVideoPlayer::isLoaded() {
    if(videoPlayer == NULL) {
        return false;
    }
    
    return [((AVFoundationVideoPlayer *)videoPlayer) isReady];
}

//----------------------------------------
bool ofxiOSVideoPlayer::isPlaying() {
    if(videoPlayer == NULL) {
        return false;
    }
    
    return [((AVFoundationVideoPlayer *)videoPlayer) isPlaying];
}

//----------------------------------------
float ofxiOSVideoPlayer::getPosition() {
    if(videoPlayer == NULL) {
        return 0;
    }
    
    return [((AVFoundationVideoPlayer *)videoPlayer) getPosition];
}

//----------------------------------------
float ofxiOSVideoPlayer::getSpeed() {
    if(videoPlayer == NULL) {
        return 0;
    }
    
    return [((AVFoundationVideoPlayer *)videoPlayer) getSpeed];
}

//----------------------------------------
float ofxiOSVideoPlayer::getDuration() {
    if(videoPlayer == NULL) {
        return 0;
    }
    
    return [((AVFoundationVideoPlayer *)videoPlayer) getDurationInSec];
}

//----------------------------------------
bool ofxiOSVideoPlayer::getIsMovieDone() {
    if(videoPlayer == NULL) {
        return false;
    }
    
    return [((AVFoundationVideoPlayer *)videoPlayer) isFinished];
}

//----------------------------------------
void ofxiOSVideoPlayer::setPaused(bool bPause) {
    if(videoPlayer == NULL) {
        return;
    }
    
    if(bPause) {
        [((AVFoundationVideoPlayer *)videoPlayer) pause];
    } else {
        [((AVFoundationVideoPlayer *)videoPlayer) play];
    }
}

//----------------------------------------
void ofxiOSVideoPlayer::setPosition(float pct) {
    if(videoPlayer == NULL) {
        return;
    }
    
    [((AVFoundationVideoPlayer *)videoPlayer) setPosition:pct];
}

//----------------------------------------
void ofxiOSVideoPlayer::setVolume(float volume) {
    if(videoPlayer == NULL) {
        return;
    }
	if ( volume > 1.0f ){
		ofLogWarning("ofxiOSVideoPlayer") << "setVolume(): expected range is 0-1, limiting requested volume " << volume << " to 1.0";
		volume = 1.0f;
	}
    [((AVFoundationVideoPlayer *)videoPlayer) setVolume:volume];    
}

//----------------------------------------
void ofxiOSVideoPlayer::setLoopState(ofLoopType state) {
    if(videoPlayer == NULL) {
        return;
    }
    
    bool bLoop = false;
    if((state == OF_LOOP_NORMAL) || 
       (state == OF_LOOP_PALINDROME)) {
        bLoop = true;
    }
    [((AVFoundationVideoPlayer *)videoPlayer) setLoop:bLoop];
}

//----------------------------------------
void ofxiOSVideoPlayer::setSpeed(float speed) {
    if(videoPlayer == NULL) {
        return;
    }
    
    [((AVFoundationVideoPlayer *)videoPlayer) setSpeed:speed];
}

//----------------------------------------
void ofxiOSVideoPlayer::setFrame(int frame) {
    if(videoPlayer == NULL) {
        return;
    }

    [((AVFoundationVideoPlayer *)videoPlayer) setFrame:frame];
}

//----------------------------------------
int	ofxiOSVideoPlayer::getCurrentFrame() {
    if(videoPlayer == NULL){
        return 0;
    }
    return [((AVFoundationVideoPlayer *)videoPlayer) getCurrentFrameNum];
}

//----------------------------------------
int	ofxiOSVideoPlayer::getTotalNumFrames() {
    if(videoPlayer == NULL){
        return 0;
    }
    return [((AVFoundationVideoPlayer *)videoPlayer) getDurationInFrames];
}

//----------------------------------------
ofLoopType	ofxiOSVideoPlayer::getLoopState() {
    if(videoPlayer == NULL) {
        return OF_LOOP_NONE;
    }
    
    bool bLoop =  [((AVFoundationVideoPlayer *)videoPlayer) getLoop];
    if(bLoop) {
        return OF_LOOP_NORMAL;
    }
    return OF_LOOP_NONE;
}

//----------------------------------------
void ofxiOSVideoPlayer::firstFrame() {
    if(videoPlayer == NULL) {
        return;
    }
    
    [((AVFoundationVideoPlayer *)videoPlayer) setPosition:0];
}

//----------------------------------------
void ofxiOSVideoPlayer::nextFrame() {
    int nextFrameNum = ofClamp(getCurrentFrame() + 1, 0, getTotalNumFrames());
    setFrame(nextFrameNum);
}

//----------------------------------------
void ofxiOSVideoPlayer::previousFrame() {
    int prevFrameNum = ofClamp(getCurrentFrame() - 1, 0, getTotalNumFrames());
    setFrame(prevFrameNum);
}

//----------------------------------------
void * ofxiOSVideoPlayer::getAVFoundationVideoPlayer() {
    return videoPlayer;
}
