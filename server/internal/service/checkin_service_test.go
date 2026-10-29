package service

import (
	"strings"
	"testing"
)

// S3-03 DoD：level 阈值映射与技术文档 6.4 一致（1/3/7/14/30/60/100/150/200/260/330/400）。
func TestTreeLevelForPoints(t *testing.T) {
	cases := []struct {
		points int
		want   int8
	}{
		{0, 1}, {1, 1}, {2, 1}, {3, 2}, {6, 2}, {7, 3}, {13, 3}, {14, 4},
		{29, 4}, {30, 5}, {59, 5}, {60, 6}, {99, 6}, {100, 7}, {150, 8},
		{200, 9}, {260, 10}, {330, 11}, {400, 12}, {1000, 12},
	}
	for _, c := range cases {
		if got := TreeLevelForPoints(c.points); got != c.want {
			t.Fatalf("TreeLevelForPoints(%d) = %d, want %d", c.points, got, c.want)
		}
	}
}

func TestCreateCheckinValidation(t *testing.T) {
	svc := &CheckinService{}
	uid := int64(1)

	cases := []struct {
		name string
		req  CreateCheckinReq
	}{
		{"品类越界", CreateCheckinReq{Category: 7, Content: "ok", Visibility: 2}},
		{"可见范围越界", CreateCheckinReq{Category: 1, Content: "ok", Visibility: 4}},
		{"空内容", CreateCheckinReq{Category: 1, Content: "", Visibility: 2}},
		{"超长内容", CreateCheckinReq{Category: 1, Content: strings.Repeat("字", 501), Visibility: 2}},
		{"图片超 9 张", CreateCheckinReq{Category: 1, Content: "ok", Visibility: 2,
			ImageURLs: []string{"1", "2", "3", "4", "5", "6", "7", "8", "9", "10"}}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			req := c.req
			if _, err := svc.Create(nil, uid, &req); err == nil {
				t.Fatalf("%s 应报参数错误", c.name)
			} else if _, ok := err.(*ValidationError); !ok {
				t.Fatalf("%s 应为 ValidationError，got %T", c.name, err)
			}
		})
	}
}
