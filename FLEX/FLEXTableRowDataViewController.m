//
//  FLEXTableRowDataViewController.m
//  FLEX
//
//  Created by Chaoshuai Lu on 7/8/20.
//
// 遇到问题联系中文翻译作者：pxx917144686

#import "FLEXTableRowDataViewController.h"
#import "FLEXMutableListSection.h"
#import "FLEXAlert.h"

@interface FLEXTableRowDataViewController ()
@property (nonatomic) NSDictionary<NSString *, NSString *> *rowsByColumn;
@end

@implementation FLEXTableRowDataViewController

#pragma mark - Initialization

+ (instancetype)rows:(NSDictionary<NSString *, id> *)rowData {
    FLEXTableRowDataViewController *controller = [self new];
    controller.rowsByColumn = rowData;
    return controller;
}

#pragma mark - Overrides

- (NSArray<FLEXTableViewSection *> *)makeSections {
    NSDictionary<NSString *, NSString *> *rowsByColumn = self.rowsByColumn;
    
    FLEXMutableListSection<NSString *> *section = [FLEXMutableListSection list:self.rowsByColumn.allKeys
        cellConfiguration:^(UITableViewCell *cell, NSString *column, NSInteger row) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.text = column;
            cell.detailTextLabel.text = rowsByColumn[column].description;
        } filterMatcher:^BOOL(NSString *filterText, NSString *column) {
            return [column localizedCaseInsensitiveContainsString:filterText] ||
                [rowsByColumn[column] localizedCaseInsensitiveContainsString:filterText];
        }
    ];
    
    section.selectionHandler = ^(UIViewController *host, NSString *column) {
        UIPasteboard.generalPasteboard.string = rowsByColumn[column].description;
        [FLEXAlert makeAlert:^(FLEXAlert *make) {
            make.title(@"列已复制到剪贴板");
            make.message(rowsByColumn[column].description);
            make.button(@"关闭").cancelStyle();
        } showFrom:host];
    };

    return @[section];
}

@end
