//
//  ZTWebView.m
//  NoWait
//
//  Created by liu nian on 16/8/15.
//  Copyright © 2016年 Shanghai Puscene Information Technology Co.,Ltd. All rights reserved.
//

#import "ZTWebView.h"
#import "NWUtility.h"
#import "Config.h"
#import <JSONKit-NoWarning/JSONKit.h>
#import "EventLogger.h"

#import "UIPlugin.h"
#import "NavigatorBarPlugin.h"
#import "AuthorizationPlugin.h"
#import "UtilPlugin.h"
#import "LocationPlugin.h"
#import "PayPlugin.h"

@interface ZTWebView ()<WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, weak) id<TCFunctionProtocol>TCFunction;

@property (nonatomic, strong) UIPlugin *uiPlugin;
@property (nonatomic, strong) NavigatorBarPlugin *navigatorBarPlugin;
@property (nonatomic, strong) AuthorizationPlugin *authorizationPlugin;
@property (nonatomic, strong) UtilPlugin *utilPlugin;
@property (nonatomic, strong) LocationPlugin *locationPlugin;
@property (nonatomic, strong) PayPlugin *payPlugin;
@end

@implementation ZTWebView

- (instancetype)initWithFrame:(CGRect)frame delegate:(id<TCFunctionProtocol>)delegate{
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    
    config.preferences = [[WKPreferences alloc] init];
    config.preferences.minimumFontSize = 10;
    config.processPool = [WKCookieSyncManager sharedInstance].processPool;
    config.preferences.javaScriptEnabled = YES;
    config.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 9.0) {
        config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    }
    config.userContentController = [[WKUserContentController alloc] init];

    
    self = [super initWithFrame:frame configuration:config];
    if (self) {
        // Initialization code
        self.TCFunction = delegate;
        self.navigationDelegate = self;
        self.UIDelegate = self;
        if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 9.0) {
            self.customUserAgent = self.userAgent;
        }
        
        [config.userContentController addScriptMessageHandler:self name:@"ui"];
        [config.userContentController addScriptMessageHandler:self name:@"navigator_bar"];
        [config.userContentController addScriptMessageHandler:self name:@"authorization"];
        [config.userContentController addScriptMessageHandler:self name:@"util"];
        [config.userContentController addScriptMessageHandler:self name:@"location"];
        [config.userContentController addScriptMessageHandler:self name:@"pay"];
        
        [config.userContentController addScriptMessageHandler:self name:@"transform"];
        
        /*
        [config.userContentController addScriptMessageHandler:self.uiPlugin name:@"ui"];
        [config.userContentController addScriptMessageHandler:self.navigatorBarPlugin name:@"navigator_bar"];
        [config.userContentController addScriptMessageHandler:self.authorizationPlugin name:@"authorization"];
        [config.userContentController addScriptMessageHandler:self.utilPlugin name:@"util"];
        [config.userContentController addScriptMessageHandler:self.locationPlugin name:@"location"];
        [config.userContentController addScriptMessageHandler:self.payPlugin name:@"pay"];
        */
        // 添加KVO监听
        [self addObserver:self
               forKeyPath:@"loading"
                  options:NSKeyValueObservingOptionNew
                  context:nil];
        [self addObserver:self
               forKeyPath:@"title"
                  options:NSKeyValueObservingOptionNew
                  context:nil];
        [self addObserver:self
               forKeyPath:@"estimatedProgress"
                  options:NSKeyValueObservingOptionNew
                  context:nil];
    }
    return self;
}

#pragma mark - private method
- (BOOL)isCorrectWirelessProcotocolScheme:(NSURL *)URL{
    return [[URL scheme] isEqualToString:@"meiwei"];
}

- (BOOL)isCorrectJumpProcotocolScheme:(NSURL*)URL {
    return [[URL scheme] isEqualToString:kMweeProtocolScheme];
}

#pragma mark - H5内部新协议
- (void)doWirelessURLSchemeWithURL:(NSURL *)URL{
    NSURLComponents *componets = [[NSURLComponents alloc] initWithURL:URL resolvingAgainstBaseURL:NO];
    NSString *host = componets.host;
    NSArray *queryItems = componets.queryItems;
    if ([host isEqualToString:@"wireless"]) {
        __block NSString *protocol = nil;
        __block NSString *target = nil;
        __block NSString *url = nil;
        __block BOOL showloading = NO;
        
        [queryItems enumerateObjectsUsingBlock:^(NSURLQueryItem *queryItem, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([queryItem.name isEqualToString:@"protocol"] && queryItem.value) {
                protocol = queryItem.value;
            }else if ([queryItem.name isEqualToString:@"url"]){
                NSData *data = [NWUtility decodeBASE64:queryItem.value];
                NSString *urlStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                url = urlStr;
            }else if ([queryItem.name isEqualToString:@"target"]){
                target = queryItem.value;
            }else if ([queryItem.name isEqualToString:@"showloading"]){
                showloading = [queryItem.value boolValue];
            }
        }];
        
        [self doJobWithProtocol:protocol target:target url:url showloading:showloading];
    }
}

//把老协议修改成新协议的格式加载
- (NSURL *)chageProtocol:(NSURL *)URL{
    NSString *url = [URL.absoluteString stringByReplacingOccurrencesOfString:@"mweeclient://" withString:@""];
    NSData *data = [url dataUsingEncoding:NSUTF8StringEncoding];
    return [NSURL URLWithString:[NSString stringWithFormat:@"meiwei://wireless?protocol=native&url=%@=&target=new&showloading=1",[NWUtility encodeBASE64:data]]];
}

/*!
 @author liunian, 16-08-09 16:08:44
 
 @brief 本地跳转
 
 @param protocol        跳转协议类型:file & web,native,打开线上链接还是本地文件,还是本地的跳转
 @param target          打开方式:target：new & current   新页面还是当前页面
 @param url             地址:
 @param showloading     是否显示loading动画:
 */
- (void)doJobWithProtocol:(NSString *)protocol target:(NSString *)target url:(NSString *)url showloading:(BOOL)showloading{
    DDLogInfo(@"[%@, %@, %@]",protocol, target, url);
    TCRouteProtocolType routeType = TCRouteProtocolTypeNone;
    if ([protocol isEqualToString:@"web"]) {
        routeType = TCRouteProtocolTypeWeb;
    }else if([protocol isEqualToString:@"file"]){
        routeType = TCRouteProtocolTypeFile;
    }else if([protocol isEqualToString:@"native"]){
        routeType = TCRouteProtocolTypeNative;
    }
    
    TCRouteTargetType targetType = TCRouteTargetTypeNone;
    if ([target isEqualToString:@"new"]) {
        targetType = TCRouteTargetTypeNew;
    }else if ([target isEqualToString:@"current"]) {
        targetType = TCRouteTargetTypeCurrent;
    }
    
    if (routeType == TCRouteProtocolTypeNone || targetType == TCRouteTargetTypeNone) {
        return;
    }
    
    [self JSBridgeWithProtocol:routeType target:targetType url:url showloading:showloading];
}
/*!
 @brief 页面跳转业务协议
 
 @param routeType    协议名:file & web,打开线上链接还是本地文件
 @param targetType   目标打开类型:new & current,新页面还是当前页面
 @param url          具体的业务指令url
 */
- (void)JSBridgeWithProtocol:(TCRouteProtocolType)routeType
                      target:(TCRouteTargetType)targetType
                         url:(NSString *)url
                 showloading:(BOOL)showloading{
    if ([_TCFunction respondsToSelector:@selector(JSBridgeWithProtocol:target:url:showloading:)]) {
        [_TCFunction JSBridgeWithProtocol:routeType target:targetType url:url showloading:showloading];
    }
}
- (void)doJobWithBusinessModel:(BusinessModel *)model{
    DDLogInfo(@"[%@, %@, %@, %@]",model.moudle, model.method, model.apiParams, model.callback);
    if ([_TCFunction respondsToSelector:@selector(JSBridgeWithBusinessModel:)]) {
        [_TCFunction JSBridgeWithBusinessModel:model];
    }
}


- (BOOL)nativeCallbackWithJsParam:(NSDictionary *)jsParam{
    DDLogInfo(@"[%@]",jsParam);
    NSString *jsonString = nil;
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsParam
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    if ([jsonData length] > 0 && error == nil){
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    NSData *eData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64Str = [NWUtility encodeBASE64:eData];
    [self toCallFunctionName:@"MWJSBridge.nativeCallback" arguments:base64Str];
    return YES;
}
- (void)toCallFunctionName:(NSString *)functionName arguments:(NSString *)argumentStr{
    argumentStr = argumentStr?argumentStr:@"";
    [self evaluateJavaScript:[NSString stringWithFormat:@"%@('%@')",functionName,argumentStr]
           completionHandler:^(id _Nullable re, NSError * _Nullable error) {}];
}

#pragma mark - public method
- (BOOL)toCallWithEmitMessageName:(NSString *)emitMessageName data:(NSDictionary *)data{
    NSMutableDictionary *jsParam = @{}.mutableCopy;
    jsParam[@"emitMessageName"] = emitMessageName;
    jsParam[@"data"] = data?data:[NSNull null];
    return [self nativeCallbackWithJsParam:jsParam];
}

- (BOOL)doCallbackWithCBID:(NSString *)cbid data:(NSDictionary *)data errorCode:(TCHybridResponseCode)errorCode errorMsg:(NSString *)errorMsg{
    if (!cbid || cbid.length == 0) {
        return NO;
    }
    errorMsg = errorMsg?errorMsg:@"";
    NSMutableDictionary *jsParam = @{@"cbId":cbid,@"errorCode":@(errorCode),@"errorMsg":errorMsg}.mutableCopy;
    jsParam[@"data"] = data?data:[NSNull null];
    return [self nativeCallbackWithJsParam:jsParam];
}

- (void)JSBridgeWithWebTitle:(NSString *)webTitle{
    
}
#pragma mark - KVO
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"loading"]) {
        NSLog(@"loading");
    } else if ([keyPath isEqualToString:@"title"]) {
        if ([_TCFunction respondsToSelector:@selector(JSBridgeWithWebTitle:)]) {
            [_TCFunction JSBridgeWithWebTitle:self.title];
        }
    } else if ([keyPath isEqualToString:@"estimatedProgress"]) {
        NSLog(@"progress: %f", self.estimatedProgress);
        //        self.progressView.progress = self.webView.estimatedProgress;
    }
    
    // 加载完成
    if (!self.loading) {
    }
}
#pragma mark - WKNavigationDelegate
// 请求开始前，会先调用此代理方法
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSURL *URL = navigationAction.request.URL;
    if ([self isCorrectWirelessProcotocolScheme:URL]) {
        [self doWirelessURLSchemeWithURL:URL];
        decisionHandler(WKNavigationActionPolicyCancel);
    }else if ([self isCorrectJumpProcotocolScheme:URL]){
        [self doWirelessURLSchemeWithURL:[self chageProtocol:URL]];
        decisionHandler(WKNavigationActionPolicyCancel);
    }else{
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

// 在响应完成时，会回调此方法
// 如果设置为不允许响应，web内容就不会传过来
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    decisionHandler(WKNavigationResponsePolicyAllow);
}

// 开始导航跳转时会回调
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(null_unspecified WKNavigation *)navigation {
    NSLog(@"%s", __FUNCTION__);
}

// 接收到重定向时会回调
- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(null_unspecified WKNavigation *)navigation {
    NSLog(@"%s", __FUNCTION__);
}

// 导航失败时会回调
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"%s", __FUNCTION__);
}

// 页面内容到达main frame时回调
- (void)webView:(WKWebView *)webView didCommitNavigation:(null_unspecified WKNavigation *)navigation {
    NSLog(@"%s", __FUNCTION__);
}

// 导航完成时，会回调（也就是页面载入完成了）
- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation {
    //通知唐超前端组本地JS加载完成
    [self toCallWithEmitMessageName:@"bridge_ready" data:nil];
    if ([_TCFunction respondsToSelector:@selector(JSBridgeLoadedFinish)]) {
        [_TCFunction JSBridgeLoadedFinish];
    }
    NSString *jsString = [NSString stringWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"trans" withExtension:@"js"]
                                                  encoding:NSUTF8StringEncoding error:nil];
    
    [self evaluateJavaScript:jsString completionHandler:^(id _Nullable value, NSError * _Nullable error) {
        NSLog(@"%@", value);
    }];
}
// 导航失败时会回调
- (void)webView:(WKWebView *)webView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error {
    if ([_TCFunction respondsToSelector:@selector(JSBridgeLoadedFinish)]) {
        [_TCFunction JSBridgeLoadedFinish];
    }
}

// 对于HTTPS的都会触发此代理，如果不要求验证，传默认就行
// 如果需要证书验证，与使用AFN进行HTTPS证书验证是一样的
- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *__nullable credential))completionHandler {
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}
#ifdef  __IPHONE_9_0
// 9.0才能使用，web内容处理中断时会触发
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    NSLog(@"%s", __FUNCTION__);
}
#endif

#pragma mark - WKUIDelegate
- (void)webViewDidClose:(WKWebView *)webView {
}
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    if ([_TCFunction respondsToSelector:@selector(JSBridgeWithAlertMessage:completionHandler:)]) {
        [_TCFunction JSBridgeWithAlertMessage:message completionHandler:completionHandler];
    }
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL result))completionHandler {
    if ([_TCFunction respondsToSelector:@selector(JSBridgeWithAlertMessage:resultCompletionHandler:)]) {
        [_TCFunction JSBridgeWithAlertMessage:message resultCompletionHandler:completionHandler];
    }
}
- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(nullable NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString * __nullable result))completionHandler {
    if ([_TCFunction respondsToSelector:@selector(JSBridgeWithAlertTextInputPanelWithPrompt:defaultText:completionHandler:)]) {
        [_TCFunction JSBridgeWithAlertTextInputPanelWithPrompt:prompt defaultText:defaultText completionHandler:completionHandler];
    }
}

#pragma mark - WKScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    //测试代码
    if ([message.name isEqualToString:@"transform"]) {
        NSLog(@"transform:%@",message.body);
        if ([message.body isEqualToString:@"jclogin"]) {
            NSString *js = [NSString stringWithFormat:@"CJLogined('%@')",@"asdfasdfasdfasdfasdf"];
            [self evaluateJavaScript:js completionHandler:^(id _Nullable value, NSError * _Nullable error) {
                
            }];
        }

        return;
    }
    if(message.body && message.name){
        NSDictionary *body = [message.body objectFromJSONString];
        NSString *plugin = body[@"plugin"];
        NSString *method = body[@"method"];
        NSDictionary *apiParams = body[@"apiParams"];
        NSString *callback = nil;
        
        if (body[@"cbId"]) {
            callback = body[@"cbId"];
        }
        BusinessModel *model = [[BusinessModel alloc]init];
        model.moudle = plugin;
        model.method = method;
        model.apiParams = apiParams;
        model.callback = callback;
        [self doJobWithBusinessModel:model];
    }
}

#pragma mark getter
- (UIPlugin *)uiPlugin{
    if (!_uiPlugin) {
        _uiPlugin = [[UIPlugin alloc] init];
    }
    return _uiPlugin;
}

- (NavigatorBarPlugin *)navigatorBarPlugin{
    if (!_navigatorBarPlugin) {
        _navigatorBarPlugin = [[NavigatorBarPlugin alloc] init];
    }
    return _navigatorBarPlugin;
}

- (AuthorizationPlugin *)authorizationPlugin{
    if (!_authorizationPlugin) {
        _authorizationPlugin = [[AuthorizationPlugin alloc] init];
    }
    return _authorizationPlugin;
}

- (UtilPlugin *)utilPlugin{
    if (!_utilPlugin) {
        _utilPlugin = [[UtilPlugin alloc] init];
    }
    return _utilPlugin;
}
- (LocationPlugin *)locationPlugin{
    if (!_locationPlugin) {
        _locationPlugin = [[LocationPlugin alloc] init];
    }
    return _locationPlugin;
}

- (PayPlugin *)payPlugin{
    if (!_payPlugin) {
        _payPlugin = [[PayPlugin alloc] init];
    }
    return _payPlugin;
}

- (NSString *)userAgent{
    NSString *userAgent = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
    // User-Agent Header; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.43
    userAgent = [NSString stringWithFormat:@"%@/%@ (%@; %@; iOS %@; Scale/%0.2f)", [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleExecutableKey] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleIdentifierKey], [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleVersionKey], [[UIDevice currentDevice] model],[NWUtility getCurrentDeviceModel], [[UIDevice currentDevice] systemVersion], [[UIScreen mainScreen] scale]];
#pragma clang diagnostic pop
    if (userAgent) {
        if (![userAgent canBeConvertedToEncoding:NSASCIIStringEncoding]) {
            NSMutableString *mutableUserAgent = [userAgent mutableCopy];
            if (CFStringTransform((__bridge CFMutableStringRef)(mutableUserAgent), NULL, (__bridge CFStringRef)@"Any-Latin; Latin-ASCII; [:^ASCII:] Remove", false)) {
                userAgent = mutableUserAgent;
            }
        }
    }
    return userAgent;
}
@end

@implementation WKCookieSyncManager
SingletonImplementation(WKCookieSyncManager);

- (WKProcessPool *)processPool{
    if (!_processPool) {
        _processPool = [[WKProcessPool alloc] init];
    }
    return _processPool;
}
@end
