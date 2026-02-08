/* See LICENSE file for copyright and license details.
 *
 * MacDrag - Drag and resize windows with modifier
 * 
 * To understand everything else, start reading main().
 */

#import <ApplicationServices/ApplicationServices.h>
#import <Cocoa/Cocoa.h>

AXUIElementRef getElementAtPos(CGPoint point);
AXUIElementRef getWinFromElement(AXUIElementRef element);
CGPoint getWinPos(AXUIElementRef window);
void setWinPos(AXUIElementRef window, CGPoint point);
CGSize getWinSize(AXUIElementRef window);
void setWinSize(AXUIElementRef window, CGSize size);
void updateWin(AXUIElementRef win);
void stopTimer();
CGEventRef callback(CGEventTapProxy proxy, CGEventType type,
                    CGEventRef event, void *refcon);

AXUIElementRef target = NULL;
CGPoint initPos, initMPos, pendingPos;
CGSize initSize, pendingSize;
static dispatch_source_t updateTimer = NULL;
static bool hasPos = false;
static bool hasSize = false;
bool dragging = false;
bool resizing = false;
bool resL = false;
bool resT = false;

AXUIElementRef getElementAtPos(CGPoint pt) {
    AXUIElementRef sys = AXUIElementCreateSystemWide(), el = NULL;
    AXUIElementCopyElementAtPosition(sys, pt.x, pt.y, &el);
    CFRelease(sys);
    return el;
}

AXUIElementRef getWinFromElement(AXUIElementRef el) {
    AXUIElementRef cur = el;
    CFRetain(cur);
    while (cur) {
        CFTypeRef role = NULL;
        if (AXUIElementCopyAttributeValue(cur, kAXRoleAttribute, &role) == kAXErrorSuccess && role) {
            bool isWin = CFStringCompare(role, kAXWindowRole, 0) == kCFCompareEqualTo;
            CFRelease(role);
            if (isWin) return cur;
        }
        CFTypeRef next = NULL;
        AXUIElementCopyAttributeValue(cur, kAXParentAttribute, &next);
        CFRelease(cur);
        cur = (AXUIElementRef)next;
    }
    return NULL;
}

CGPoint getWinPos(AXUIElementRef win) {
    CFTypeRef v = NULL; CGPoint p = CGPointZero;
    if (AXUIElementCopyAttributeValue(win, kAXPositionAttribute, &v) == kAXErrorSuccess)
        AXValueGetValue(v, kAXValueCGPointType, &p); CFRelease(v);
    return p;
}

void setWinPos(AXUIElementRef win, CGPoint p) {
    AXValueRef v = AXValueCreate(kAXValueCGPointType, &p);
    if (v) { AXUIElementSetAttributeValue(win, kAXPositionAttribute, v); CFRelease(v); }
}

CGSize getWinSize(AXUIElementRef win) {
    CFTypeRef v = NULL; CGSize s = CGSizeZero;
    if (AXUIElementCopyAttributeValue(win, kAXSizeAttribute, &v) == kAXErrorSuccess) {
        AXValueGetValue(v, kAXValueCGSizeType, &s); CFRelease(v);
    }
    return s;
}

void setWinSize(AXUIElementRef win, CGSize s) {
    AXValueRef v = AXValueCreate(kAXValueCGSizeType, &s);
    if (v) { AXUIElementSetAttributeValue(win, kAXSizeAttribute, v); CFRelease(v); }
}

void updateWin(AXUIElementRef win) {
    if (updateTimer) return;
    CFRetain(win);
    updateTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
    dispatch_source_set_timer(updateTimer, DISPATCH_TIME_NOW, 16 * NSEC_PER_MSEC, 1 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(updateTimer, ^{
        if (hasPos) { setWinPos(win, pendingPos); hasPos = false; }
        if (hasSize) { setWinSize(win, pendingSize); hasSize = false; }
    });
    dispatch_source_set_cancel_handler(updateTimer, ^{ CFRelease(win); });
    dispatch_resume(updateTimer);
}

void stopTimer() {
    if (!updateTimer) return;
    dispatch_source_cancel(updateTimer);
    updateTimer = NULL;
}

CGEventRef callback(CGEventTapProxy proxy, CGEventType type,
                    CGEventRef event, void *refcon)
{
    CGEventFlags flags = CGEventGetFlags(event);
    bool alt = (flags & kCGEventFlagMaskAlternate) != 0;

    if (!alt) {
        dragging = false;
        resizing = false;
        if (target) {
            CFRelease(target);
            target = NULL;
        }
        return event;
    }

    CGPoint mouseLoc = CGEventGetLocation(event);

    // Mouse Down
    if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown) {
        AXUIElementRef el = getElementAtPos(mouseLoc), win = el ? getWinFromElement(el) : NULL;
        if (el) CFRelease(el);
        if (win) {
            if (target) CFRelease(target);
            target = win;
            initMPos = mouseLoc;
            initPos = getWinPos(win);
            initSize = getWinSize(win);
            if (type == kCGEventLeftMouseDown) dragging = true;
            else {
                resizing = true;
                resL = mouseLoc.x < initPos.x + initSize.width / 2;
                resT = mouseLoc.y < initPos.y + initSize.height / 2;
            }
            return NULL;
        }
    }

    // Dragging / Resizing
    if (target && (dragging || resizing)) {
        CGFloat dx = mouseLoc.x - initMPos.x, dy = mouseLoc.y - initMPos.y;
        if (dragging) {
            pendingPos = CGPointMake(initPos.x + dx, initPos.y + dy);
            hasPos = true;
        } else {
            CGFloat min = 100.0;
            CGFloat w = MAX(min, initSize.width + (resL ? -dx : dx));
            CGFloat h = MAX(min, initSize.height + (resT ? -dy : dy));
            pendingPos = CGPointMake(initPos.x + (resL ? (w == min ? initSize.width - min : dx) : 0),
                                    initPos.y + (resT ? (h == min ? initSize.height - min : dy) : 0));
            pendingSize = CGSizeMake(w, h);
            hasPos = hasSize = true;
        }
        updateWin(target);
        if (type != kCGEventLeftMouseUp && type != kCGEventRightMouseUp) return NULL;
    }

    // Mouse Up
    if ((type == kCGEventLeftMouseUp && dragging) || (type == kCGEventRightMouseUp && resizing)) {
        dragging = resizing = false;
        stopTimer();
        if (target) { CFRelease(target); target = NULL; }
        return NULL;
    }


    return event;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    printf("Started MacDrag.\n");

    CGEventMask eventMask =
        (1 << kCGEventLeftMouseDown) | (1 << kCGEventLeftMouseUp) |
        (1 << kCGEventLeftMouseDragged) | (1 << kCGEventRightMouseDown) |
        (1 << kCGEventRightMouseUp) | (1 << kCGEventRightMouseDragged);

    CFMachPortRef eventTap = CGEventTapCreate(
        kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
        eventMask, callback, NULL);

    if (!eventTap) {
      fprintf(stderr, "Failed to create event tap. is Accessibility enabled?\n");
      exit(1);
    }

    CFRunLoopSourceRef loop =
        CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), loop, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);
    CFRunLoopRun();
  }
  return 0;
}
