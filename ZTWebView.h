//
//  ZTWebView.h
//  NoWait
//
//  Created by liu nian on 16/8/15.
//  Copyright © 2016年 Shanghai Puscene Information Technology Co.,Ltd. All rights reserved.
//

#import <WebKit/WebKit.h>
#import "TCFunctionProtocol.h"
#import "Singelton.h"

@interface ZTWebView : WKWebView
- (instancetype)initWithFrame:(CGRect)frame delegate:(id<TCFunctionProtocol>)delegate;

/*!
 @brief 主动调用JS函数
 
 @param emitMessageName 函数或者业务名
 @param data            参数数组
 
 @return 调用结果
 */
- (BOOL)toCallWithEmitMessageName:(NSString *)emitMessageName data:(NSDictionary *)data;

/*!
 @brief 当本地执行JS业务之后需要回调数据给JS时调用
 
 @param cbid      回调函数标识，该函数标识是在JS调用本地功能时传入必须为真
 @param data      具体的业务数据参数数组
 @param errorCode 错误码定义
 @param errorMsg  错误的消息提示
 
 @return 调用结果
 */
- (BOOL)doCallbackWithCBID:(NSString *)cbid data:(NSDictionary *)data errorCode:(TCHybridResponseCode)errorCode errorMsg:(NSString *)errorMsg;
@end

@interface WKCookieSyncManager : NSObject
@property (nonatomic, strong) WKProcessPool *processPool;
SingletonInterface(WKCookieSyncManager);
@end