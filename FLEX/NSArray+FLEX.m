//
//  NSArray+FLEX.m
//  FLEX
//
//  由 Tanner Bennett 创建于 9/25/19.
//  版权所有 © 2020 FLEX Team. 保留所有权利。
//

#import "NSArray+FLEX.h"

#define FLEXArrayClassIsMutable(me) ([[self class] isSubclassOfClass:[NSMutableArray class]])

@implementation NSArray (Functional)

- (__kindof NSArray *)flex_mapped:(id (^)(id, NSUInteger))mapFunc {
    NSMutableArray *map = [NSMutableArray new];
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        id ret = mapFunc(obj, idx);
        if (ret) {
            [map addObject:ret];
        }
    }];

    if (self.count < 2048 && !FLEXArrayClassIsMutable(self)) {
        return map.copy;
    }

    return map;
}

- (__kindof NSArray *)flex_flatmapped:(NSArray *(^)(id, NSUInteger))block {
    NSMutableArray *array = [NSMutableArray new];
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSArray *toAdd = block(obj, idx);
        if (toAdd) {
            [array addObjectsFromArray:toAdd];
        }
    }];

    if (array.count < 2048 && !FLEXArrayClassIsMutable(self)) {
        return array.copy;
    }

    return array;
}

- (NSArray *)flex_filtered:(BOOL (^)(id, NSUInteger))filterFunc {
    return [self flex_mapped:^id(id obj, NSUInteger idx) {
        return filterFunc(obj, idx) ? obj : nil;
    }];
}

- (void)flex_forEach:(void(^)(id, NSUInteger))block {
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        block(obj, idx);
    }];
}

- (instancetype)flex_subArrayUpto:(NSUInteger)maxLength {
    if (maxLength > self.count) {
        if (FLEXArrayClassIsMutable(self)) {
            return self.mutableCopy;
        }
        
        return self;
    }
    
    return [self subarrayWithRange:NSMakeRange(0, maxLength)];
}

+ (__kindof NSArray *)flex_forEachUpTo:(NSUInteger)bound map:(id(^)(NSUInteger))block {
    NSMutableArray *array = [NSMutableArray new];
    for (NSUInteger i = 0; i < bound; i++) {
        id obj = block(i);
        if (obj) {
            [array addObject:obj];
        }
    }

    // 出于性能原因，不复制大型数组
    if (bound < 2048 && !FLEXArrayClassIsMutable(self)) {
        return array.copy;
    }

    return array;
}

+ (instancetype)flex_mapped:(id<NSFastEnumeration>)collection block:(id(^)(id obj, NSUInteger idx))mapFunc {
    NSMutableArray *array = [NSMutableArray new];
    NSInteger idx = 0;
    for (id obj in collection) {
        id ret = mapFunc(obj, idx++);
        if (ret) {
            [array addObject:ret];
        }
    }

    // 出于性能原因，不复制大型数组
    if (array.count < 2048) {
        return array.copy;
    }

    return array;
}

- (instancetype)flex_sortedUsingSelector:(SEL)selector {
    if (FLEXArrayClassIsMutable(self)) {
        NSMutableArray *me = (id)self;
        [me sortUsingSelector:selector];
        return me;
    } else {
        return [self sortedArrayUsingSelector:selector];
    }
}

- (id)flex_firstWhere:(BOOL (^)(id))meetsCriteria {
    for (id e in self) {
        if (meetsCriteria(e)) {
            return e;
        }
    }
    
    return nil;
}

@end


@implementation NSMutableArray (Functional)

- (void)flex_filter:(BOOL (^)(id, NSUInteger))keepObject {
    NSMutableIndexSet *toRemove = [NSMutableIndexSet new];
    
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if (!keepObject(obj, idx)) {
            [toRemove addIndex:idx];
        }
    }];
    
    [self removeObjectsAtIndexes:toRemove];
}

@end
