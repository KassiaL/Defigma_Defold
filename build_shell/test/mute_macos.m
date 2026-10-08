#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

__attribute__((constructor)) static void mute_player_nodes(void)
{
	Method play = class_getInstanceMethod([AVAudioPlayerNode class], @selector(play));
	void (*original)(id, SEL) = (void (*)(id, SEL))method_getImplementation(play);
	method_setImplementation(play, imp_implementationWithBlock(^(AVAudioPlayerNode *player) {
		player.volume = 0.0f;
		original(player, @selector(play));
	}));
}
