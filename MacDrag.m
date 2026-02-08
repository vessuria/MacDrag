#import <ApplicationServices/ApplicationServices.h>
#import <Cocoa/Cocoa.h>

AXUIElementRef getElementAtPos(CGPoint point);
AXUIElementRef getWinFromElement(AXUIElementRef element);
CGPoint getWinPos(AXUIElementRef window);
void setWinPos(AXUIElementRef window, CGPoint point);
CGSize getWinSize(AXUIElementRef window);
void setWinSize(AXUIElementRef window, CGSize size);
CGEventRef callback(CGEventTapProxy proxy, CGEventType type,
                    CGEventRef event, void *refcon);

AXUIElementRef target = NULL;
CGPoint initPos;
CGSize initSize;
CGPoint initMPos;
bool dragging = false;
bool resizing = false;
bool resizeLeft = false;
bool resizeTop = false;

AXUIElementRef getElementAtPos(CGPoint point) {
  AXUIElementRef systemwide = AXUIElementCreateSystemWide();
  AXUIElementRef element = NULL;
  AXError result = AXUIElementCopyElementAtPosition(
    systemwide, point.x, point.y, &element);
  CFRelease(systemwide);

  if (result == kAXErrorSuccess) return element;

  return NULL;
}

AXUIElementRef getWinFromElement(AXUIElementRef element) {
  AXUIElementRef curElement = element;
  CFRetain(curElement);

  while (true) {
    CFTypeRef role = NULL;
    AXError result = AXUIElementCopyAttributeValue(
      curElement, kAXRoleAttribute, &role);

    if (result == kAXErrorSuccess && role != NULL) {
      if (CFStringCompare((CFStringRef)role, kAXWindowRole, 0) == kCFCompareEqualTo) {
        CFRelease(role);
        return curElement;
      }
      CFRelease(role);
    }

    CFTypeRef parent = NULL;
    AXError parentResult = AXUIElementCopyAttributeValue(
      curElement, kAXParentAttribute, &parent);

    CFRelease(curElement);
    if (parentResult == kAXErrorSuccess && parent != NULL)
      curElement = (AXUIElementRef)parent;
    else return NULL;
  }
}

CGPoint getWinPos(AXUIElementRef window) {
  CFTypeRef posVal = NULL;
  AXError result = AXUIElementCopyAttributeValue(
    window, kAXPositionAttribute, &posVal);
  CGPoint point = CGPointZero;

  if (result == kAXErrorSuccess && posVal != NULL) {
    AXValueGetValue((AXValueRef)posVal, kAXValueCGPointType, &point);
    CFRelease(posVal);
  }
  return point;
}

void setWinPos(AXUIElementRef window, CGPoint point) {
  AXValueRef posVal = AXValueCreate(kAXValueCGPointType, &point);
  if (posVal) {
    AXUIElementSetAttributeValue(window, kAXPositionAttribute, posVal);
    CFRelease(posVal);
  }
}

CGSize getWinSize(AXUIElementRef window) {
  CFTypeRef sizeVal = NULL;
  AXError result =
      AXUIElementCopyAttributeValue(window, kAXSizeAttribute, &sizeVal);
  CGSize size = CGSizeZero;

  if (result == kAXErrorSuccess && sizeVal != NULL) {
    AXValueGetValue((AXValueRef)sizeVal, kAXValueCGSizeType, &size);
    CFRelease(sizeVal);
  }
  return size;
}

void setWinSize(AXUIElementRef window, CGSize size) {
  AXValueRef sizeVal = AXValueCreate(kAXValueCGSizeType, &size);
  if (sizeVal) {
    AXUIElementSetAttributeValue(window, kAXSizeAttribute, sizeVal);
    CFRelease(sizeVal);
  }
}

CGEventRef callback(CGEventTapProxy proxy, CGEventType type,
                         CGEventRef event, void *refcon) {
  CGEventFlags flags = CGEventGetFlags(event);
  bool alt = (flags & kCGEventFlagMaskAlternate) != 0;

  if (!alt) {
    if (dragging || resizing) {
      dragging = false;
      resizing = false;
      if (target) {
        CFRelease(target);
        target = NULL;
      }
    }
    return event;
  }

  CGPoint mouseLoc = CGEventGetLocation(event);

  if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown) {
    AXUIElementRef element = getElementAtPos(mouseLoc);
    if (element) {
      AXUIElementRef window = getWinFromElement(element);
      CFRelease(element);

      if (window) {
        if (target) CFRelease(target);
        target = window;

        initMPos = mouseLoc;
        initPos = getWinPos(window);
        initSize = getWinSize(window);

        if (type == kCGEventLeftMouseDown) {
          dragging = true;
          return NULL;
        } else if (type == kCGEventRightMouseDown) {
          resizing = true;
          resizeLeft = (mouseLoc.x < initPos.x + initSize.width / 2);
          resizeTop = (mouseLoc.y < initPos.y + initSize.height / 2);
          return NULL;
        }
      }
    }
  }

  if (type == kCGEventLeftMouseDragged && dragging && target) {
    CGFloat deltaX = mouseLoc.x - initMPos.x;
    CGFloat deltaY = mouseLoc.y - initMPos.y;

    CGPoint newPosition = CGPointMake(initPos.x + deltaX, initPos.y + deltaY);
    setWinPos(target, newPosition);
    return NULL;
  }

  if (type == kCGEventRightMouseDragged && resizing && target) {
    CGFloat deltaX = mouseLoc.x - initMPos.x;
    CGFloat deltaY = mouseLoc.y - initMPos.y;

    CGFloat minSize = 100.0;

    CGFloat newWidth =
        MAX(minSize, initSize.width + (resizeLeft ? -deltaX : deltaX));
    CGFloat newHeight =
        MAX(minSize, initSize.height + (resizeTop ? -deltaY : deltaY));

    CGFloat newX =
        initPos.x + (resizeLeft ?
        (newWidth == minSize ?initSize.width - minSize : deltaX) : 0);

    CGFloat newY =
        initPos.y + (resizeTop ?
        (newHeight == minSize ? initSize.height - minSize : deltaY) : 0);

    setWinPos(target, CGPointMake(newX, newY));
    setWinSize(target, CGSizeMake(newWidth, newHeight));
    return NULL;
  }

  if ((type == kCGEventLeftMouseUp && dragging) ||
      (type == kCGEventRightMouseUp && resizing)) {
    dragging = false;
    resizing = false;
    if (target) {
      CFRelease(target);
      target = NULL;
    }
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
