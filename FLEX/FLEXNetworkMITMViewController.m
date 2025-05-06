//
//  FLEXNetworkMITMViewController.m
//  Flipboard
//
//  Created by Ryan Olson on 2/8/15.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

// 遇到问题联系中文翻译作者：pxx917144686

#import "FLEXColor.h"
#import "FLEXUtility.h"
#import "FLEXMITMDataSource.h"
#import "FLEXNetworkMITMViewController.h"
#import "FLEXNetworkTransaction.h"
#import "FLEXNetworkRecorder.h"
#import "FLEXNetworkObserver.h"
#import "FLEXNetworkTransactionCell.h"
#import "FLEXHTTPTransactionDetailController.h"
#import "FLEXNetworkSettingsController.h"
#import "FLEXObjectExplorerFactory.h"
#import "FLEXGlobalsViewController.h"
#import "FLEXWebViewController.h"
#import "UIBarButtonItem+FLEX.h"
#import "FLEXResources.h"
#import "NSUserDefaults+FLEX.h"

#define kFirebaseAvailable NSClassFromString(@"FIRDocumentReference")

typedef NS_ENUM(NSInteger, FLEXNetworkObserverMode) {
    FLEXNetworkObserverModeFirebase = 0,
    FLEXNetworkObserverModeREST,
    FLEXNetworkObserverModeWebsockets,
};

@interface FLEXNetworkMITMViewController ()

@property (nonatomic) BOOL updateInProgress;
@property (nonatomic) BOOL pendingReload;

@property (nonatomic) FLEXNetworkObserverMode mode;

@property (nonatomic, readonly) FLEXMITMDataSource<FLEXNetworkTransaction *> *dataSource;
@property (nonatomic, readonly) FLEXMITMDataSource<FLEXHTTPTransaction *> *HTTPDataSource;
@property (nonatomic, readonly) FLEXMITMDataSource<FLEXWebsocketTransaction *> *websocketDataSource;
@property (nonatomic, readonly) FLEXMITMDataSource<FLEXFirebaseTransaction *> *firebaseDataSource;

@end

@implementation FLEXNetworkMITMViewController

#pragma mark - Lifecycle

- (id)init {
    return [self initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.showsSearchBar = YES;
    self.pinSearchBar = YES;
    self.showSearchBarInitially = NO;
    NSMutableArray *scopeTitles = [NSMutableArray arrayWithObject:@"REST"];
    
    _HTTPDataSource = [FLEXMITMDataSource dataSourceWithProvider:^NSArray * {
        return FLEXNetworkRecorder.defaultRecorder.HTTPTransactions;
    }];

    if (kFirebaseAvailable) {
        _firebaseDataSource = [FLEXMITMDataSource dataSourceWithProvider:^NSArray * {
            return FLEXNetworkRecorder.defaultRecorder.firebaseTransactions;
        }];
        [scopeTitles insertObject:@"Firebase" atIndex:0]; // First space
    }

    [scopeTitles addObject:@"Websockets"]; // Last space
    _websocketDataSource = [FLEXMITMDataSource dataSourceWithProvider:^NSArray * {
        if (@available(iOS 13.0, *)) {
            // iOS 13+ code
            return FLEXNetworkRecorder.defaultRecorder.websocketTransactions;
        } else {
            // Fallback code for iOS <13
            return @[];
        }
    }];
    
    // Scopes will only be shown if we have either firebase or websockets available
    self.searchController.searchBar.showsScopeBar = scopeTitles.count > 1;
    self.searchController.searchBar.scopeButtonTitles = scopeTitles;
    self.mode = NSUserDefaults.standardUserDefaults.flex_lastNetworkObserverMode;

    [self addToolbarItems:@[
        [UIBarButtonItem
            flex_itemWithImage:FLEXResources.gearIcon
            target:self
            action:@selector(settingsButtonTapped:)
        ],
        [[UIBarButtonItem
          flex_systemItem:UIBarButtonSystemItemTrash
          target:self
          action:@selector(trashButtonTapped:)
        ] flex_withTintColor:UIColor.redColor]
    ]];

    [self.tableView
        registerClass:FLEXNetworkTransactionCell.class
        forCellReuseIdentifier:FLEXNetworkTransactionCell.reuseID
    ];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = FLEXNetworkTransactionCell.preferredCellHeight;

    [self registerForNotifications];
    [self updateTransactions:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Reload the table if we received updates while not on-screen
    if (self.pendingReload) {
        [self.tableView reloadData];
        self.pendingReload = NO;
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)registerForNotifications {
    NSDictionary *notifications = @{
        kFLEXNetworkRecorderNewTransactionNotification:
            NSStringFromSelector(@selector(handleNewTransactionRecordedNotification:)),
        kFLEXNetworkRecorderTransactionUpdatedNotification:
            NSStringFromSelector(@selector(handleTransactionUpdatedNotification:)),
        kFLEXNetworkRecorderTransactionsClearedNotification:
            NSStringFromSelector(@selector(handleTransactionsClearedNotification:)),
        kFLEXNetworkObserverEnabledStateChangedNotification:
            NSStringFromSelector(@selector(handleNetworkObserverEnabledStateChangedNotification:)),
    };
    
    for (NSString *name in notifications.allKeys) {
        [NSNotificationCenter.defaultCenter addObserver:self
            selector:NSSelectorFromString(notifications[name]) name:name object:nil
        ];
    }
}


#pragma mark - Private

#pragma mark Button Actions

- (void)settingsButtonTapped:(UIBarButtonItem *)sender {
    UIViewController *settings = [FLEXNetworkSettingsController new];
    settings.navigationItem.rightBarButtonItem = FLEXBarButtonItemSystem(
        Done, self, @selector(settingsViewControllerDoneTapped:)
    );
    settings.title = @"网络监听开关";
    
    // This is not a FLEXNavigationController because it is not intended as a new tab
    UIViewController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)trashButtonTapped:(UIBarButtonItem *)sender {
    [FLEXAlert makeSheet:^(FLEXAlert *make) {
        BOOL clearAll = !self.dataSource.isFiltered;
        if (!clearAll) {
            make.title(@"清除过滤请求？");
            make.message(@"这只会删除此屏幕上与您的搜索字符串匹配的请求。");
        } else {
            make.title(@"清除所有记录的请求？");
            make.message(@"这是无法撤销的。");
        }
        
        make.button(@"取消").cancelStyle();
        make.button(@"清空").destructiveStyle().handler(^(NSArray *strings) {
            if (clearAll) {
                [FLEXNetworkRecorder.defaultRecorder clearRecordedActivity];
            } else {
                FLEXNetworkTransactionKind kind = (FLEXNetworkTransactionKind)self.mode;
                [FLEXNetworkRecorder.defaultRecorder clearRecordedActivity:kind matching:self.searchText];
            }
        });
    } showFrom:self source:sender];
}

- (void)settingsViewControllerDoneTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark Transactions

- (FLEXNetworkObserverMode)mode {
    FLEXNetworkObserverMode mode = self.searchController.searchBar.selectedScopeButtonIndex;
    switch (mode) {
        case FLEXNetworkObserverModeFirebase:
            if (kFirebaseAvailable) {
                return FLEXNetworkObserverModeFirebase;
            }

            return FLEXNetworkObserverModeREST;
        case FLEXNetworkObserverModeREST:
            if (kFirebaseAvailable) {
                return FLEXNetworkObserverModeREST;
            }

            return FLEXNetworkObserverModeWebsockets;
        case FLEXNetworkObserverModeWebsockets:
            return FLEXNetworkObserverModeWebsockets;
    }
}

- (void)setMode:(FLEXNetworkObserverMode)mode {
    switch (mode) {
        case FLEXNetworkObserverModeFirebase:
            // Will default to REST if Firebase is unavailable
            break;
        case FLEXNetworkObserverModeREST:
            // Firebase will become REST when Firebase is unavailable
            if (!kFirebaseAvailable) {
                mode--;
            }
            break;
        case FLEXNetworkObserverModeWebsockets:
            // Default to REST if Websockets are unavailable
            if (@available(iOS 13.0, *)) {
                // Websockets 可用
            } else {
                mode--;
            }
            // Firebase will become REST when Firebase is unavailable
            if (!kFirebaseAvailable) {
                mode--;
            }
    }

    self.searchController.searchBar.selectedScopeButtonIndex = mode;
}

- (FLEXMITMDataSource<FLEXNetworkTransaction *> *)dataSource {
    switch (self.mode) {
        case FLEXNetworkObserverModeREST:
            return self.HTTPDataSource;
        case FLEXNetworkObserverModeWebsockets:
            return self.websocketDataSource;
        case FLEXNetworkObserverModeFirebase:
            return self.firebaseDataSource;
    }
}

- (void)updateTransactions:(void(^)(void))callback {
    id completion = ^(FLEXMITMDataSource *dataSource) {
        // Update byte count
        [self updateFirstSectionHeader];
        if (callback && dataSource == self.dataSource) callback();
    };
    
    [self.HTTPDataSource reloadData:completion];
    [self.websocketDataSource reloadData:completion];
    [self.firebaseDataSource reloadData:completion];
}


#pragma mark Header

- (void)updateFirstSectionHeader {
    UIView *view = [self.tableView headerViewForSection:0];
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *headerView = (UITableViewHeaderFooterView *)view;
        headerView.textLabel.text = [self headerText];
        [headerView setNeedsLayout];
    }
}

- (NSString *)headerText {
    long long bytesReceived = self.dataSource.bytesReceived;
    NSInteger totalRequests = self.dataSource.transactions.count;
    
    NSString *byteCountText = [NSByteCountFormatter
        stringFromByteCount:bytesReceived countStyle:NSByteCountFormatterCountStyleBinary
    ];
    NSString *requestsText = totalRequests == 1 ? @"Request" : @"Requests";
    
    // Exclude byte count from Firebase
    if (self.mode == FLEXNetworkObserverModeFirebase) {
        return [NSString stringWithFormat:@"%@ %@",
            @(totalRequests), requestsText
        ];
    }
    
    return [NSString stringWithFormat:@"%@ %@ (%@ received)",
        @(totalRequests), requestsText, byteCountText
    ];
}


#pragma mark - FLEXGlobalsEntry

+ (NSString *)globalsEntryTitle:(FLEXGlobalsRow)row {
    return @"📡  网络监听";
}

+ (FLEXGlobalsEntryRowAction)globalsEntryRowAction:(FLEXGlobalsRow)row {
    return ^(UITableViewController *host) {
        if (FLEXNetworkObserver.isEnabled) {
            [host.navigationController pushViewController:[
                self globalsEntryViewController:row
            ] animated:YES];
        } else {
            [FLEXAlert makeAlert:^(FLEXAlert *make) {
                make.title(@"网络监视器当前禁用");
                make.message(@"您必须启用网络监控才能继续。");
                
                make.button(@"打开").preferred().handler(^(NSArray<NSString *> *strings) {
                    FLEXNetworkObserver.enabled = YES;
                    [host.navigationController pushViewController:[
                        self globalsEntryViewController:row
                    ] animated:YES];
                });
                make.button(@"取消").cancelStyle();
            } showFrom:host];
        }
    };
}

+ (UIViewController *)globalsEntryViewController:(FLEXGlobalsRow)row {
    UIViewController *controller = [self new];
    controller.title = [self globalsEntryTitle:row];
    return controller;
}


#pragma mark - Notification Handlers

- (void)handleNewTransactionRecordedNotification:(NSNotification *)notification {
    [self tryUpdateTransactions];
}

- (void)tryUpdateTransactions {
    // Don't do any view updating if we aren't in the view hierarchy
    if (!self.viewIfLoaded.window) {
        [self updateTransactions:nil];
        self.pendingReload = YES;
        return;
    }
    
    // Let the previous row insert animation finish before starting a new one to avoid stomping.
    // We'll try calling the method again when the insertion completes,
    // and we properly no-op if there haven't been changes.
    if (self.updateInProgress) {
        return;
    }
    
    self.updateInProgress = YES;

    // Get state before update
    NSString *currentFilter = self.searchText;
    FLEXNetworkObserverMode currentMode = self.mode;
    NSInteger existingRowCount = self.dataSource.transactions.count;
    
    [self updateTransactions:^{
        // Compare to state after update
        NSString *newFilter = self.searchText;
        FLEXNetworkObserverMode newMode = self.mode;
        NSInteger newRowCount = self.dataSource.transactions.count;
        NSInteger rowCountDiff = newRowCount - existingRowCount;
        
        // Abort if the observation mode changed, or if the search field text changed
        if (newMode != currentMode || ![currentFilter isEqualToString:newFilter]) {
            self.updateInProgress = NO;
            return;
        }
        
        if (rowCountDiff) {
            // Insert animation if we're at the top.
            if (self.tableView.contentOffset.y <= 0.0 && rowCountDiff > 0) {
                [CATransaction begin];
                
                [CATransaction setCompletionBlock:^{
                    self.updateInProgress = NO;
                    // This isn't an infinite loop, it won't run a third time
                    // if there were no new transactions the second time
                    [self tryUpdateTransactions];
                }];
                
                NSMutableArray<NSIndexPath *> *indexPathsToReload = [NSMutableArray new];
                for (NSInteger row = 0; row < rowCountDiff; row++) {
                    [indexPathsToReload addObject:[NSIndexPath indexPathForRow:row inSection:0]];
                }

                [self.tableView insertRowsAtIndexPaths:indexPathsToReload withRowAnimation:UITableViewRowAnimationAutomatic];
                [CATransaction commit];
            } else {
                // Maintain the user's position if they've scrolled down.
                CGSize existingContentSize = self.tableView.contentSize;
                [self.tableView reloadData];
                CGFloat contentHeightChange = self.tableView.contentSize.height - existingContentSize.height;
                self.tableView.contentOffset = CGPointMake(self.tableView.contentOffset.x, self.tableView.contentOffset.y + contentHeightChange);
                self.updateInProgress = NO;
            }
        } else {
            self.updateInProgress = NO;
        }
    }];
}

- (void)handleTransactionUpdatedNotification:(NSNotification *)notification {
    [self.HTTPDataSource reloadByteCounts];
    [self.websocketDataSource reloadByteCounts];
    // Don't need to reload Firebase here

    FLEXNetworkTransaction *transaction = notification.userInfo[kFLEXNetworkRecorderUserInfoTransactionKey];

    // Update both the main table view and search table view if needed.
    for (FLEXNetworkTransactionCell *cell in self.tableView.visibleCells) {
        if ([cell.transaction isEqual:transaction]) {
            // Using -[UITableView reloadRowsAtIndexPaths:withRowAnimation:] is overkill here and kicks off a lot of
            // work that can make the table view somewhat unresponsive when lots of updates are streaming in.
            // We just need to tell the cell that it needs to re-layout.
            [cell setNeedsLayout];
            break;
        }
    }
    
    [self updateFirstSectionHeader];
}

- (void)handleTransactionsClearedNotification:(NSNotification *)notification {
    [self updateTransactions:^{
        [self.tableView reloadData];
    }];
}

- (void)handleNetworkObserverEnabledStateChangedNotification:(NSNotification *)notification {
    // Update the header, which displays a warning when network debugging is disabled
    [self updateFirstSectionHeader];
}


#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataSource.transactions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self headerText];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *headerView = (UITableViewHeaderFooterView *)view;
        headerView.textLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    FLEXNetworkTransactionCell *cell = [tableView
        dequeueReusableCellWithIdentifier:FLEXNetworkTransactionCell.reuseID
        forIndexPath:indexPath
    ];
    
    cell.transaction = [self transactionAtIndexPath:indexPath];

    // Since we insert from the top, assign background colors bottom up to keep them consistent for each transaction.
    NSInteger totalRows = [tableView numberOfRowsInSection:indexPath.section];
    if ((totalRows - indexPath.row) % 2 == 0) {
        cell.backgroundColor = FLEXColor.secondaryBackgroundColor;
    } else {
        cell.backgroundColor = FLEXColor.primaryBackgroundColor;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (self.mode) {
        case FLEXNetworkObserverModeREST: {
            FLEXHTTPTransaction *transaction = [self HTTPTransactionAtIndexPath:indexPath];
            UIViewController *details = [FLEXHTTPTransactionDetailController withTransaction:transaction];
            [self.navigationController pushViewController:details animated:YES];
            break;
        }
            
        case FLEXNetworkObserverModeWebsockets: {
            if (@available(iOS 13.0, *)) { // This check will never fail
                FLEXWebsocketTransaction *transaction = [self websocketTransactionAtIndexPath:indexPath];
                
                UIViewController *details = nil;
                if (transaction.message.type == NSURLSessionWebSocketMessageTypeData) {
                    details = [FLEXObjectExplorerFactory explorerViewControllerForObject:transaction.message.data];
                } else {
                    details = [[FLEXWebViewController alloc] initWithText:transaction.message.string];
                }
                
                [self.navigationController pushViewController:details animated:YES];
            }
            break;
        }
        
        case FLEXNetworkObserverModeFirebase: {
            FLEXFirebaseTransaction *transaction = [self firebaseTransactionAtIndexPath:indexPath];
//            id obj = transaction.documents.count == 1 ? transaction.documents.firstObject : transaction.documents;
            UIViewController *explorer = [FLEXObjectExplorerFactory explorerViewControllerForObject:transaction];
            [self.navigationController pushViewController:explorer animated:YES];
        }
    }
}


#pragma mark - Menu Actions

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    return action == @selector(copy:);
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    if (action == @selector(copy:)) {
        UIPasteboard.generalPasteboard.string = [self transactionAtIndexPath:indexPath].copyString;
    }
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point __IOS_AVAILABLE(13.0) {
    
    FLEXNetworkTransaction *transaction = [self transactionAtIndexPath:indexPath];
    
    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
        previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
            UIAction *copy = [UIAction
                actionWithTitle:@"复制URL"
                image:nil
                identifier:nil
                handler:^(__kindof UIAction *action) {
                    UIPasteboard.generalPasteboard.string = transaction.copyString;
                }
            ];
        
            NSArray *children = @[copy];
            if (self.mode == FLEXNetworkObserverModeREST) {
                NSURLRequest *request = [self HTTPTransactionAtIndexPath:indexPath].request;
                UIAction *denylist = [UIAction
                    actionWithTitle:[NSString stringWithFormat:@"Exclude '%@'", request.URL.host]
                    image:nil
                    identifier:nil
                    handler:^(__kindof UIAction *action) {
                        NSMutableArray *denylist =  FLEXNetworkRecorder.defaultRecorder.hostDenylist;
                        [denylist addObject:request.URL.host];
                        [FLEXNetworkRecorder.defaultRecorder clearExcludedTransactions];
                        [FLEXNetworkRecorder.defaultRecorder synchronizeDenylist];
                        [self tryUpdateTransactions];
                    }
                ];
                
                children = [children arrayByAddingObject:denylist];
            }
            return [UIMenu
                menuWithTitle:@"" image:nil identifier:nil
                options:UIMenuOptionsDisplayInline
                children:children
            ];
        }
    ];
}

- (FLEXNetworkTransaction *)transactionAtIndexPath:(NSIndexPath *)indexPath {
    return self.dataSource.transactions[indexPath.row];
}

- (FLEXHTTPTransaction *)HTTPTransactionAtIndexPath:(NSIndexPath *)indexPath {
    return self.HTTPDataSource.transactions[indexPath.row];
}

- (FLEXWebsocketTransaction *)websocketTransactionAtIndexPath:(NSIndexPath *)indexPath {
    return self.websocketDataSource.transactions[indexPath.row];
}

- (FLEXFirebaseTransaction *)firebaseTransactionAtIndexPath:(NSIndexPath *)indexPath {
    return self.firebaseDataSource.transactions[indexPath.row];
}

#pragma mark - Search Bar

- (void)updateSearchResults:(NSString *)searchString {
    id callback = ^(FLEXMITMDataSource *dataSource) {
        if (self.dataSource == dataSource) {
            [self.tableView reloadData];
        }
    };
    
    [self.HTTPDataSource filter:searchString completion:callback];
    [self.websocketDataSource filter:searchString completion:callback];
    [self.firebaseDataSource filter:searchString completion:callback];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)newScope {
    [self updateFirstSectionHeader];
    [self.tableView reloadData];

    NSUserDefaults.standardUserDefaults.flex_lastNetworkObserverMode = self.mode;
}

- (void)willDismissSearchController:(UISearchController *)searchController {
    [self.tableView reloadData];
}

- (NSString *)localizedMethodString:(NSString *)method {
    NSDictionary *methodMap = @{
        @"GET": @"获取",
        @"POST": @"提交",
        @"PUT": @"更新",
        @"DELETE": @"删除",
        @"HEAD": @"HEAD请求",
        @"PATCH": @"部分更新",
        @"OPTIONS": @"选项查询"
    };
    return methodMap[method] ?: method;
}

@end
