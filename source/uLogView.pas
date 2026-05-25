unit uLogView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, Forms,
  LCLType, LCLIntf, Math;

type
  TLogView = class(TCustomControl)
  private
    FScrollV      : TScrollBar;
    FScrollH      : TScrollBar;
    FTopIndex     : Integer;
    FItemIndex    : Integer;
    FCount        : Integer;
    FItemHeight   : Integer;   // fixed base height from font
    FScrollWidth  : Integer;   // logical content width for horiz scroll
    FHorzOffset   : Integer;   // horizontal scroll position in pixels
    FShowHorzScroll: Boolean;
    FSelected     : array of Boolean;
    FSelCapacity  : Integer;
    FAnchorIndex  : Integer;
    FOnDrawItem   : TDrawItemEvent;
    FOnMeasureItem: TMeasureItemEvent;

    const SCROLLBAR_W = 17;

    procedure ScrollVChange(Sender: TObject);
    procedure ScrollHChange(Sender: TObject);
    procedure SetTopIndexInternal(AValue: Integer);
    procedure SetTopIndex(AValue: Integer);
    procedure SetItemIndex(AValue: Integer);
    procedure SetScrollWidth(AValue: Integer);
    procedure SetShowHorzScroll(AValue: Boolean);
    function  GetSelected(AIndex: Integer): Boolean;
    procedure SetSelected(AIndex: Integer; AValue: Boolean);
    function  GetItemHeight(AIndex: Integer): Integer; inline;
    function  GetVisibleCount: Integer;
    procedure UpdateScrollBars;
    function  PaintW: Integer; inline;
    function  PaintH: Integer; inline;
    function  IndexAtY(AY: Integer): Integer;
    procedure GrowSelected(ANewCount: Integer);
    procedure MouseWheelHandler(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);

  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;

  public
    constructor Create(AOwner: TComponent); override;

    procedure SetCount(ACount: Integer);
    procedure AppendItem;
    procedure Clear;
    procedure UpdateFont;
    procedure EnsureVisible(AIndex: Integer);
    procedure ScrollToEnd;   // letzte Zeile am unteren Rand

    property TopIndex  : Integer  read FTopIndex  write SetTopIndex;
    property ItemIndex : Integer  read FItemIndex write SetItemIndex;
    property Count     : Integer  read FCount;
    property Selected  [AIndex: Integer]: Boolean
      read GetSelected write SetSelected;
    property ScrollWidth    : Integer read FScrollWidth  write SetScrollWidth;
    property ShowHorzScrollbar: Boolean
      read FShowHorzScroll write SetShowHorzScroll;
    property OnDrawItem   : TDrawItemEvent    read FOnDrawItem    write FOnDrawItem;
    property OnMeasureItem: TMeasureItemEvent read FOnMeasureItem write FOnMeasureItem;
  end;

implementation

{ TLogView }

constructor TLogView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csDoubleClicks, csCaptureMouse];
  TabStop      := True;
  DoubleBuffered := True;

  FScrollV := TScrollBar.Create(Self);
  FScrollV.Parent      := Self;
  FScrollV.Kind        := sbVertical;
  FScrollV.SmallChange := 1;
  FScrollV.LargeChange := 10;
  FScrollV.Min         := 0;
  FScrollV.Max         := 0;
  FScrollV.OnChange    := @ScrollVChange;

  FScrollH := TScrollBar.Create(Self);
  FScrollH.Parent      := Self;
  FScrollH.Kind        := sbHorizontal;
  FScrollH.SmallChange := 20;
  FScrollH.Min         := 0;
  FScrollH.Max         := 0;
  FScrollH.Visible     := False;
  FScrollH.OnChange    := @ScrollHChange;

  FTopIndex     := 0;
  FItemIndex    := -1;
  FAnchorIndex  := -1;
  FCount        := 0;
  FItemHeight   := 18;
  FSelCapacity  := 0;

  OnMouseWheel := @MouseWheelHandler;
end;

function TLogView.PaintW: Integer;
begin
  Result := ClientWidth - SCROLLBAR_W;
  if Result < 0 then Result := 0;
end;

function TLogView.PaintH: Integer;
begin
  Result := ClientHeight;
  if FShowHorzScroll and FScrollH.Visible then
    Dec(Result, SCROLLBAR_W);
  if Result < 0 then Result := 0;
end;

function TLogView.GetItemHeight(AIndex: Integer): Integer;
begin
  Result := FItemHeight;
  if Assigned(FOnMeasureItem) then
    FOnMeasureItem(Self, AIndex, Result);
end;

function TLogView.GetVisibleCount: Integer;
begin
  if FItemHeight <= 0 then Result := 1
  else Result := Max(1, PaintH div FItemHeight);
end;

procedure TLogView.UpdateScrollBars;
var
  VisCount, HMax, HBottom: Integer;
begin
  VisCount := GetVisibleCount;
  HBottom  := IfThen(FShowHorzScroll and FScrollH.Visible, SCROLLBAR_W, 0);

  // Position and size vertical scrollbar
  FScrollV.SetBounds(ClientWidth - SCROLLBAR_W, 0,
    SCROLLBAR_W, ClientHeight - HBottom);

  if FCount > VisCount then
  begin
    FScrollV.LargeChange := Max(1, VisCount);
    FScrollV.Min         := 0;
    FScrollV.Max         := FCount - 1;
    FScrollV.Visible     := True;
    if FScrollV.Position <> FTopIndex then
      FScrollV.Position := FTopIndex;
  end
  else
  begin
    FScrollV.Visible := False;
    FTopIndex := 0;
  end;

  // Horizontal scrollbar
  if FShowHorzScroll and (FScrollWidth > PaintW) then
  begin
    HMax := FScrollWidth - PaintW;
    if FHorzOffset > HMax then FHorzOffset := HMax;
    FScrollH.SetBounds(0, ClientHeight - SCROLLBAR_W,
      ClientWidth - SCROLLBAR_W, SCROLLBAR_W);
    FScrollH.LargeChange := Max(1, PaintW);
    FScrollH.Min         := 0;
    FScrollH.Max         := FScrollWidth;
    if FScrollH.Position <> FHorzOffset then
      FScrollH.Position := FHorzOffset;
    FScrollH.Visible := True;
  end
  else
  begin
    FScrollH.Visible := False;
    FHorzOffset := 0;
  end;
end;

procedure TLogView.Paint;
var
  i, Y, H  : Integer;
  ARect    : TRect;
  State    : TOwnerDrawState;
  W, PH    : Integer;
  NewH     : Integer;
begin
  // Update font and item height from live canvas
  Canvas.Font.Assign(Font);
  NewH := Max(4, Canvas.TextHeight('Agqjy') + 4);
  if NewH <> FItemHeight then
  begin
    FItemHeight := NewH;
    UpdateScrollBars;
  end;

  W  := PaintW;
  PH := PaintH;

  if FCount = 0 then
  begin
    Canvas.Brush.Color := Color;
    Canvas.FillRect(Rect(0, 0, W, PH));
    Exit;
  end;

  Y := 0;
  i := FTopIndex;

  while (Y < PH) and (i < FCount) do
  begin
    H := GetItemHeight(i);

    // ARect shifts left by FHorzOffset so text is rendered at correct logical X
    ARect := Rect(-FHorzOffset, Y,
      Max(W, FScrollWidth) - FHorzOffset, Y + H);

    State := [];
    if (i = FItemIndex) or GetSelected(i) then
      Include(State, odSelected);
    if Focused and (i = FItemIndex) then
      Include(State, odFocused);

    if Assigned(FOnDrawItem) then
      FOnDrawItem(Self, i, ARect, State)
    else
    begin
      if odSelected in State then
        Canvas.Brush.Color := clHighlight
      else
        Canvas.Brush.Color := Color;
      Canvas.FillRect(Rect(0, Y, W, Y + H));
    end;

    Inc(Y, H);
    Inc(i);
  end;

  // Fill area below last item
  if Y < PH then
  begin
    Canvas.Brush.Color := Color;
    Canvas.FillRect(Rect(0, Y, W, PH));
  end;
end;

procedure TLogView.Resize;
begin
  inherited Resize;
  UpdateScrollBars;
  Invalidate;
end;

procedure TLogView.SetTopIndexInternal(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if (FCount > 0) and (AValue >= FCount) then AValue := FCount - 1;
  if AValue <> FTopIndex then
  begin
    FTopIndex := AValue;
    UpdateScrollBars;
    Invalidate;
  end;
end;

procedure TLogView.SetTopIndex(AValue: Integer);
begin
  SetTopIndexInternal(AValue);
end;

procedure TLogView.SetItemIndex(AValue: Integer);
begin
  if AValue < -1 then AValue := -1;
  if AValue >= FCount then AValue := FCount - 1;
  if AValue <> FItemIndex then
  begin
    FItemIndex := AValue;
    EnsureVisible(AValue);
  end
  else
    Invalidate;
end;

procedure TLogView.EnsureVisible(AIndex: Integer);
var
  VC: Integer;
begin
  if AIndex < 0 then Exit;
  VC := GetVisibleCount;
  if AIndex < FTopIndex then
    SetTopIndexInternal(AIndex)
  else if AIndex >= FTopIndex + VC then
    SetTopIndexInternal(AIndex - VC + 1)
  else
    Invalidate;
end;

procedure TLogView.GrowSelected(ANewCount: Integer);
begin
  if ANewCount > FSelCapacity then
  begin
    FSelCapacity := Max(ANewCount, FSelCapacity + 4096);
    SetLength(FSelected, FSelCapacity);
  end;
end;

function TLogView.GetSelected(AIndex: Integer): Boolean;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    Result := False
  else if AIndex < Length(FSelected) then
    Result := FSelected[AIndex]
  else
    Result := False;
end;

procedure TLogView.SetSelected(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex >= 0) and (AIndex < FCount) then
  begin
    GrowSelected(AIndex + 1);
    FSelected[AIndex] := AValue;
  end;
end;

function TLogView.IndexAtY(AY: Integer): Integer;
var
  Y, H, i: Integer;
begin
  Y := 0;
  i := FTopIndex;
  while (i < FCount) do
  begin
    H := GetItemHeight(i);
    if (AY >= Y) and (AY < Y + H) then
    begin
      Result := i;
      Exit;
    end;
    Inc(Y, H);
    Inc(i);
    if Y >= PaintH then Break;
  end;
  Result := -1;
end;

procedure TLogView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Idx, j: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if not Focused then SetFocus;
  Idx := IndexAtY(Y);
  if Idx < 0 then Exit;

  if (ssShift in Shift) and (FAnchorIndex >= 0) then
  begin
    // Range selection
    GrowSelected(FCount);
    FillChar(FSelected[0], FCount * SizeOf(Boolean), 0);
    for j := Min(FAnchorIndex, Idx) to Max(FAnchorIndex, Idx) do
      if j < FCount then FSelected[j] := True;
    FItemIndex := Idx;
  end
  else if ssCtrl in Shift then
  begin
    // Toggle
    GrowSelected(Idx + 1);
    FSelected[Idx]  := not FSelected[Idx];
    FItemIndex      := Idx;
    FAnchorIndex    := Idx;
  end
  else
  begin
    // Single click — clear all, select one
    if FCount <= FSelCapacity then
      FillChar(FSelected[0], FCount * SizeOf(Boolean), 0);
    FItemIndex   := Idx;
    FAnchorIndex := Idx;
  end;
  Invalidate;
end;

procedure TLogView.KeyDown(var Key: Word; Shift: TShiftState);
var
  VC: Integer;
begin
  inherited KeyDown(Key, Shift);
  VC := GetVisibleCount;
  case Key of
    VK_UP:    SetItemIndex(FItemIndex - 1);
    VK_DOWN:  SetItemIndex(FItemIndex + 1);
    VK_PRIOR: SetItemIndex(FItemIndex - VC);
    VK_NEXT:  SetItemIndex(FItemIndex + VC);
    VK_HOME:  if ssCtrl in Shift then SetItemIndex(0)
              else SetTopIndexInternal(0);
    VK_END:   if ssCtrl in Shift then SetItemIndex(FCount - 1)
              else SetTopIndexInternal(FCount - 1);
  else
    Exit;
  end;
  Key := 0;
end;

procedure TLogView.MouseWheelHandler(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  SetTopIndexInternal(FTopIndex - (WheelDelta div 120) * 3);
  Handled := True;
end;

procedure TLogView.ScrollVChange(Sender: TObject);
begin
  if FScrollV.Position <> FTopIndex then
  begin
    FTopIndex := FScrollV.Position;
    Invalidate;
  end;
end;

procedure TLogView.ScrollHChange(Sender: TObject);
begin
  if FScrollH.Position <> FHorzOffset then
  begin
    FHorzOffset := FScrollH.Position;
    Invalidate;
  end;
end;

procedure TLogView.SetScrollWidth(AValue: Integer);
begin
  if AValue <> FScrollWidth then
  begin
    FScrollWidth := AValue;
    UpdateScrollBars;
  end;
end;

procedure TLogView.SetShowHorzScroll(AValue: Boolean);
begin
  if AValue <> FShowHorzScroll then
  begin
    FShowHorzScroll := AValue;
    UpdateScrollBars;
    Invalidate;
  end;
end;

procedure TLogView.UpdateFont;
begin
  Canvas.Font.Assign(Font);
  FItemHeight := Max(4, Canvas.TextHeight('Agqjy') + 4);
  UpdateScrollBars;
  Invalidate;
end;

procedure TLogView.SetCount(ACount: Integer);
begin
  FCount := ACount;
  if ACount = 0 then
  begin
    FTopIndex    := 0;
    FItemIndex   := -1;
    FAnchorIndex := -1;
    FillChar(FSelected[0], FSelCapacity * SizeOf(Boolean), 0);
  end
  else
  begin
    GrowSelected(ACount);
    if FItemIndex >= ACount then FItemIndex := ACount - 1;
    if FTopIndex  >= ACount then FTopIndex  := ACount - 1;
  end;
  UpdateScrollBars;
  Invalidate;
end;

procedure TLogView.AppendItem;
begin
  Inc(FCount);
  GrowSelected(FCount);
  // Lightweight scrollbar update: just adjust Max
  if FScrollV.Visible then
    FScrollV.Max := FCount - 1
  else if FCount > GetVisibleCount then
  begin
    FScrollV.Min := 0;
    FScrollV.Max := FCount - 1;
    FScrollV.LargeChange := GetVisibleCount;
    FScrollV.Visible := True;
    FScrollV.SetBounds(ClientWidth - SCROLLBAR_W, 0,
      SCROLLBAR_W, ClientHeight);
  end;
  Invalidate;
end;

procedure TLogView.ScrollToEnd;
var
  VC, NewTop: Integer;
begin
  if FCount <= 0 then Exit;
  VC     := GetVisibleCount;
  NewTop := FCount - VC;
  if NewTop < 0 then NewTop := 0;
  FItemIndex := FCount - 1;
  SetTopIndexInternal(NewTop);
end;

procedure TLogView.Clear;
begin
  SetCount(0);
end;

end.
