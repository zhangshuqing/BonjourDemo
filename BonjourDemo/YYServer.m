//
//  YYServer.m
//  BonjourDemo
//
//  Created by 张树青 on 2017/3/22.
//  Copyright © 2017年 zsq. All rights reserved.
//

#import "YYServer.h"
#import "Server.h"
#import "Connection.h"

@interface YYServer ()<ServerDelegate, ConnectionDelegate>

@property (nonatomic, retain) Server * server;
@property (nonatomic, retain) NSMutableSet * clients;
@property (nonatomic, retain) dispatch_source_t timer;
@property (nonatomic, assign) int index;
@property (nonatomic, retain) NSThread *thread;
@property (nonatomic, assign) double sendTime;
@property (nonatomic, assign) double receiveTime;
@property (nonatomic, retain) NSPort *port;
@property (nonatomic, retain) NSMutableDictionary *clientsDict;
@end

@implementation YYServer

+ (instancetype)shareInsatance{
    static YYServer *_server;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _server = [[YYServer alloc] init];
    });
    return _server;
}

- (id)init
{
    self = [super init];
    if (self) {
        _clients = [[NSMutableSet alloc] init];
        _clientsDict = [NSMutableDictionary dictionary];
    }
    return self;
}


- (void)startServerWithName:(NSString *)name{
    
    [self stopServer];
    
    Server *server = [[Server alloc] init];
    self.server = server;
    [server release];
    self.server.name = name;
    self.server.delegate = self;
    
    NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:nil];
    self.thread = thread;
    [thread release];
    [self.thread start];
    
    [self performSelector:@selector(action) onThread:self.thread withObject:nil waitUntilDone:NO ];

}

- (void)action{
    BOOL succeed = [self.server start];
    if ( !succeed ) {
        self.server = nil;
        return;
    }
    //[self startHeart];
}
- (void)run{
    //只要往RunLoop中添加了  timer、source或者observer就会继续执行，一个Run Loop通常必须包含一个输入源或者定时器来监听事件，如果一个都没有，Run Loop启动后立即退出。
    
    //1、添加一个input source
    NSPort *port = [NSPort port];
    self.port = port;
    [[NSRunLoop currentRunLoop] addPort:self.port forMode:NSRunLoopCommonModes];
    [[NSRunLoop currentRunLoop] run];
    //        //2、添加一个定时器
    //    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0/60.0 target:self selector:@selector(test) userInfo:nil repeats:YES];
    //    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    //    [[NSRunLoop currentRunLoop] run];
    
}
- (void)test{
    [self sendMessage:@""];
}


- (void)startHeart{
  
    dispatch_queue_t myQueue=dispatch_queue_create("HeartQueue", NULL);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, myQueue);
    [myQueue release];
    self.timer = timer;
    [timer release];
    dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC));
    uint64_t interval = (uint64_t)(1.0 * NSEC_PER_SEC);
    dispatch_source_set_timer(self.timer, start, interval, 0);
    __block typeof(self) weakself = self;
    // 设置回调
    dispatch_source_set_event_handler(self.timer, ^{
        [weakself sendMessage:@""];
    });
    
    // 启动定时器
    dispatch_resume(self.timer);
    
}

- (void)stopServer{
    if (self.timer) {
        dispatch_source_cancel(self.timer);
        self.timer = nil;
    }
    
    
    if (self.thread) {
        [self performSelector:@selector(exitThread) onThread:self.thread withObject:nil waitUntilDone:NO];
    }
    
    [self.clients makeObjectsPerformSelector:@selector(close)];
    [self.clients removeAllObjects];
    [self.server stop];
    self.server = nil;
}
- (void)exitThread{
    [[NSRunLoop currentRunLoop] removePort:self.port forMode:NSRunLoopCommonModes];
    [NSThread exit];
    self.thread = nil;
}

- (void)sendMessage:(NSString *)message{
    [self performSelector:@selector(sendMessageOnSubThread:) onThread:self.thread withObject:message waitUntilDone:NO];
}

- (void)sendMessageOnSubThread:(NSString *)message{
    [self.clients makeObjectsPerformSelector:@selector(sendNetworkPacket:) withObject:message];
    if (message && message.length>0) {
        NSNumber *str = @([[NSDate date] timeIntervalSince1970]);
        self.index ++;
        self.sendTime = [str doubleValue];
        NSLog(@"server发送时间:%@, %d", str, self.index);
    }

}

#pragma mark - server delegate
- (void) serverFailed:(Server *)server reason:(NSString *)reason
{
    [self stopServer];
}

- (void) handleNewConnection:(Connection *)connection
{
    //发现新的连接
    connection.delegate = self;
    [self.clients addObject:connection];
    
}

#pragma mark - connection delegate
- (void) connectionAttemptFailed:(Connection *)connection{
    [self.clients removeObject:connection];
}
- (void) connectionTerminated:(Connection *)connection
{
    [self.clients removeObject:connection];
}

- (void) receivedNetworkPacket:(NSString *)packet viaConnection:(Connection *)connection
{
    NSLog(@"%@", packet);
    if (packet && packet.length>0) {
        NSData *packetData = [packet dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:packetData options:NSJSONReadingMutableLeaves error:nil];
        if (dict && ![dict isKindOfClass:[NSNull class]]) {
            if ([dict[@"packet"][@"header"][@"packet_type"] isEqualToString:@"S2T_3"]) {
                //心跳报文处理
                NSString *phone = dict[@"packet"][@"data"][@"phone"];
                if (phone) {
                    [self.clients setValue:connection forKey:phone];
                }
                //对学生端心跳进行应答
                [connection sendNetworkPacket:@""];
                
                
            } else {
                //其他报文处理
                
            }
        }

    } else {
        NSNumber *str = @([[NSDate date] timeIntervalSince1970]);
        self.receiveTime = [str doubleValue];
        NSLog(@"server收到时间:%@, %f, %d\n\n", [str stringValue],(self.receiveTime - self.sendTime)* 1000 / 2, self.index);
    }
}


- (void)dealloc
{

    [_clients release];
    [_clientsDict release];
    [_server stop];
    [_server release];
    if (self.thread) {
        [self performSelector:@selector(exitThread) onThread:self.thread withObject:nil waitUntilDone:NO];
    }
    [_thread release];
    [_port release];
    dispatch_cancel(_timer);
    [_timer release];
    [super dealloc];
}
@end
