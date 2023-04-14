//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SignalRecipient.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger SignalRecipientSchemaVersion = 1;

const uint64_t SignalRecipientDistantPastUnregisteredTimestamp = 1;

@interface SignalRecipient ()

@property (nonatomic) NSOrderedSet<NSNumber *> *devices;
@property (nonatomic) NSUInteger recipientSchemaVersion;

@end

#pragma mark -

@implementation SignalRecipient

- (instancetype)initWithServiceId:(nullable ServiceIdObjC *)serviceId phoneNumber:(nullable E164ObjC *)phoneNumber
{
    self = [super init];

    if (!self) {
        return self;
    }

    _recipientUUID = serviceId.uuidValue.UUIDString;
    _recipientPhoneNumber = phoneNumber.stringValue;
    _recipientSchemaVersion = SignalRecipientSchemaVersion;
    // New recipients start out as "unregistered in the distant past"
    _unregisteredAtTimestamp = @(SignalRecipientDistantPastUnregisteredTimestamp);
    _devices = [NSOrderedSet orderedSet];

    return self;
}

#if TESTABLE_BUILD
- (instancetype)initWithPhoneNumber:(nullable NSString *)phoneNumber
                               uuid:(nullable NSUUID *)uuid
                            devices:(NSArray<NSNumber *> *)devices
{
    OWSAssertDebug(phoneNumber.length > 0 || uuid.UUIDString.length > 0);

    self = [super init];

    if (!self) {
        return self;
    }

    _recipientUUID = uuid.UUIDString;
    _recipientPhoneNumber = phoneNumber;
    _recipientSchemaVersion = SignalRecipientSchemaVersion;
    _devices = [NSOrderedSet orderedSetWithArray:devices];
    if (!devices.count) {
        _unregisteredAtTimestamp = @(NSDate.ows_millisecondTimeStamp);
    }

    return self;
}
#endif

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_devices == nil) {
        _devices = [NSOrderedSet new];
    }

    // Migrating from an everyone has a phone number world to a
    // world in which we have UUIDs
    if (_recipientSchemaVersion < 1) {
        // Copy uniqueId to recipientPhoneNumber
        _recipientPhoneNumber = [coder decodeObjectForKey:@"uniqueId"];

        OWSAssert(_recipientPhoneNumber != nil);
    }

    // Since we use device count to determine whether a user is registered or not,
    // ensure the local user always has at least *this* device.
    if (![_devices containsObject:@(OWSDeviceObjc.primaryDeviceId)]) {
        if (self.address.isLocalAddress) {
            OWSLogInfo(@"Adding primary device to self recipient.");
            [self addDevices:[NSSet setWithObject:@(OWSDeviceObjc.primaryDeviceId)] source:SignalRecipientSourceLocal];
        }
    }

    _recipientSchemaVersion = SignalRecipientSchemaVersion;

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                         devices:(NSOrderedSet<NSNumber *> *)devices
            recipientPhoneNumber:(nullable NSString *)recipientPhoneNumber
                   recipientUUID:(nullable NSString *)recipientUUID
         unregisteredAtTimestamp:(nullable NSNumber *)unregisteredAtTimestamp
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _devices = devices;
    _recipientPhoneNumber = recipientPhoneNumber;
    _recipientUUID = recipientUUID;
    _unregisteredAtTimestamp = unregisteredAtTimestamp;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

+ (AnySignalRecipientFinder *)recipientFinder
{
    return [AnySignalRecipientFinder new];
}

+ (nullable instancetype)getRecipientForAddress:(SignalServiceAddress *)address
                                mustHaveDevices:(BOOL)mustHaveDevices
                                    transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(address.isValid);
    SignalRecipient *_Nullable signalRecipient =
        [self.modelReadCaches.signalRecipientReadCache getSignalRecipientForAddress:address transaction:transaction];
    if (mustHaveDevices && signalRecipient.devices.count < 1) {
        return nil;
    }
    return signalRecipient;
}

#pragma mark -

- (void)addDevices:(NSSet<NSNumber *> *)devices source:(SignalRecipientSource)source
{
    OWSAssertDebug(devices.count > 0);

    NSMutableOrderedSet<NSNumber *> *updatedDevices = [self.devices mutableCopy];
    [updatedDevices unionSet:devices];
    self.devices = [updatedDevices copy];

    if ((self.devices.count > 0) && (self.unregisteredAtTimestamp != nil)) {
        [self setUnregisteredAtTimestamp:nil source:source];
    }
}

- (void)removeDevices:(NSSet<NSNumber *> *)devices source:(SignalRecipientSource)source
{
    NSMutableOrderedSet<NSNumber *> *updatedDevices = [self.devices mutableCopy];
    [updatedDevices minusSet:devices];
    self.devices = [updatedDevices copy];

    if ((self.devices.count == 0) && (self.unregisteredAtTimestamp == nil)) {
        [self setUnregisteredAtTimestamp:@(NSDate.ows_millisecondTimeStamp) source:source];
    }
}

- (void)removeAllDevicesWithUnregisteredAtTimestamp:(uint64_t)unregisteredAtTimestamp
                                             source:(SignalRecipientSource)source
{
    self.devices = [NSOrderedSet orderedSet];

    [self setUnregisteredAtTimestamp:@(unregisteredAtTimestamp) source:source];
}

- (void)setUnregisteredAtTimestamp:(nullable NSNumber *)unregisteredAtTimestamp source:(SignalRecipientSource)source
{
    if ([NSObject isNullableObject:unregisteredAtTimestamp equalTo:self.unregisteredAtTimestamp]) {
        return;
    }
    self.unregisteredAtTimestamp = unregisteredAtTimestamp;

    if (source != SignalRecipientSourceStorageService) {
        [self.storageServiceManager recordPendingUpdatesWithUpdatedAccountIds:@[ self.accountId ]];
    }
}

- (void)updateWithDevicesToAdd:(NSArray<NSNumber *> *)devicesToAdd
               devicesToRemove:(NSArray<NSNumber *> *)devicesToRemove
                   transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devicesToAdd.count > 0 || devicesToRemove.count > 0);

    // Add before we remove, since removeDevicesFromRecipient:...
    // can markRecipientAsUnregistered:... if the recipient has
    // no devices left.
    if (devicesToAdd.count > 0) {
        OWSLogInfo(@"devicesToAdd: %@ for %@", devicesToAdd, self.address);
        [self updateWithDevicesToAdd:[NSSet setWithArray:devicesToAdd] transaction:transaction];
    }
    if (devicesToRemove.count > 0) {
        OWSLogInfo(@"devicesToRemove: %@ for %@", devicesToRemove, self.address);
        [self updateWithDevicesToRemove:[NSSet setWithArray:devicesToRemove] transaction:transaction];
    }

    // Device changes
    dispatch_async(dispatch_get_main_queue(), ^{
        // Device changes can affect the UD access mode for a recipient,
        // so we need to fetch the profile for this user to update UD access mode.
        [self.profileManager fetchProfileForAddress:self.address authedAccount:AuthedAccount.implicit];

        if (self.address.isLocalAddress) {
            if (OWSWebSocket.verboseLogging) {
                OWSLogInfo(@"");
            }
            [self.socketManager cycleSocket];
        }
    });
}

- (void)updateWithDevicesToAdd:(NSSet<NSNumber *> *)devices transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devices.count > 0);
    OWSLogDebug(@"adding devices: %@, to recipient: %@", devices, self);

    [self anyReloadWithTransaction:transaction];
    [self anyUpdateWithTransaction:transaction
                             block:^(SignalRecipient *signalRecipient) {
                                 [signalRecipient addDevices:devices source:SignalRecipientSourceLocal];
                             }];
}

- (void)updateWithDevicesToRemove:(NSSet<NSNumber *> *)devices transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devices.count > 0);

    OWSLogDebug(@"removing devices: %@, from registered recipient: %@", devices, self);
    [self anyReloadWithTransaction:transaction ignoreMissing:YES];
    [self anyUpdateWithTransaction:transaction
                             block:^(SignalRecipient *signalRecipient) {
                                 [signalRecipient removeDevices:devices source:SignalRecipientSourceLocal];
                             }];
}

#pragma mark -

- (SignalServiceAddress *)address
{
    return [[SignalServiceAddress alloc] initWithUuidString:self.recipientUUID phoneNumber:self.recipientPhoneNumber];
}

#pragma mark -

- (NSComparisonResult)compare:(SignalRecipient *)other
{
    return [self.address compare:other.address];
}

- (void)anyWillInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillInsertWithTransaction:transaction];

    OWSLogVerbose(@"Inserted signal recipient: %@ (%lu)", self.address, (unsigned long)self.devices.count);
}

- (void)anyWillUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillUpdateWithTransaction:transaction];

    OWSLogVerbose(@"Updated signal recipient: %@ (%lu)", self.address, (unsigned long)self.devices.count);
}

+ (BOOL)isRegisteredRecipient:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(address.isValid);
    return nil != [self getRecipientForAddress:address mustHaveDevices:YES transaction:transaction];
}

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidInsertWithTransaction:transaction];

    [self.modelReadCaches.signalRecipientReadCache didInsertOrUpdateSignalRecipient:self transaction:transaction];

    OWSLogInfo(@"Inserted: %@", self.address);
}

- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidUpdateWithTransaction:transaction];

    [self.modelReadCaches.signalRecipientReadCache didInsertOrUpdateSignalRecipient:self transaction:transaction];
}

- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidRemoveWithTransaction:transaction];

    [self.modelReadCaches.signalRecipientReadCache didRemoveSignalRecipient:self transaction:transaction];
    [self.storageServiceManager recordPendingUpdatesWithUpdatedAccountIds:@[ self.accountId ]];
}

+ (TSFTSIndexMode)FTSIndexMode
{
    return TSFTSIndexModeAlways;
}

@end

NS_ASSUME_NONNULL_END
